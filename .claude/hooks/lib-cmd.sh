#!/usr/bin/env bash
# Shared helpers for .claude/hooks/guard-bash.sh. Sourced, never run.
#
# cmd_segments    stdin: a shell command line. Prints one simple command per line with
#                 heredoc bodies and quoted strings blanked, so prose inside a commit
#                 message cannot trip a rule. Splits on && || ; | ( ) and backticks.
# cmd_payloads    stdin: the raw command line. Prints the quoted payload of every
#                 `bash -c '...'` / `sh -c "..."` / `eval '...'`, so a rule cannot be
#                 dodged by wrapping the command in a shell.
# all_segments    both of the above, payloads one level deep.
# parse_seg       sets SEG_ENV (NAME=value words), PROG (basename of the program, after
#                 wrappers such as sudo/rtk and interpreters such as bash/uv run/python -m)
#                 and ARGS (its arguments).
# has_arg         has_arg a b c: true when any ARGS element equals one of the words.
# git_push_reason protected-branch regex, cwd: prints why a `git push` hits a protected
#                 branch; returns 1 when PROG is not a push or the push is harmless.

cmd_segments() {
    awk '
        skip { t = $0; sub(/^\t+/, "", t); if (t == delim) skip = 0; next }
        { print }
        $0 !~ /<<</ && match($0, /<<-?[ \t]*[^ \t<]+/) {
            d = substr($0, RSTART, RLENGTH)
            gsub(/<<-?[ \t]*|["\047]/, "", d)
            delim = d; skip = 1
        }
    ' |
        sed -E "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g" |
        sed -E 's/(&&|\|\||;|\||\(|\)|`)/\n/g' |
        sed -E '/^[[:space:]]*$/d'
}

cmd_payloads() {
    grep -oE "(bash|sh|zsh|dash|fish)( +-[a-zA-Z]+)* +-[a-zA-Z]*c +('[^']*'|\"[^\"]*\")|eval +('[^']*'|\"[^\"]*\")" |
        sed -E "s/^[^'\"]*['\"]//; s/['\"]\$//" || true
}

all_segments() {
    local raw payload
    raw=$(cat)
    printf '%s\n' "$raw" | cmd_segments
    printf '%s\n' "$raw" | cmd_payloads | while IFS= read -r payload; do
        printf '%s\n' "$payload" | cmd_segments
    done
}

parse_seg() {
    local -a t=()
    read -r -a t <<<"$1"
    SEG_ENV=()
    PROG=""
    ARGS=()
    local i=0 w
    while [ "$i" -lt "${#t[@]}" ]; do
        w=${t[$i]}
        case "$w" in
        [A-Za-z_]*=*) SEG_ENV+=("$w") ;;
        sudo | time | command | env | nohup | exec | rtk | proxy | builtin | nice | if | then | do | else | elif | while | until | '!' | '{') ;;
        -*) ;;
        *) break ;;
        esac
        i=$((i + 1))
    done
    local -a r=("${t[@]:$i}")
    # `bash -n FILE`, `python -m py_compile FILE`: a syntax check, not a run of FILE
    case "${r[0]:-}" in
    bash | sh | zsh | dash | */bash | */sh)
        if [ "${r[1]:-}" = -n ]; then PROG="(syntax-check)"; return 0; fi
        ;;
    python | python3 | */python | */python3)
        local x
        for x in "${r[@]:1}"; do [ "$x" = py_compile ] && { PROG="(syntax-check)"; return 0; }; done
        ;;
    esac
    while [ "${#r[@]}" -gt 0 ]; do
        w=${r[0]##*/}
        case "$w" in
        bash | sh | zsh | dash | python | python3 | python3.* | node | npx | uv | run | tsx)
            r=("${r[@]:1}")
            while [ "${#r[@]}" -gt 0 ] && [[ ${r[0]} == -* ]]; do r=("${r[@]:1}"); done
            ;;
        *) break ;;
        esac
    done
    if [ "${#r[@]}" -gt 0 ]; then
        PROG=${r[0]##*/}
        ARGS=("${r[@]:1}")
    fi
}

has_arg() {
    local a w
    for a in "${ARGS[@]+"${ARGS[@]}"}"; do
        for w in "$@"; do [ "$a" = "$w" ] && return 0; done
    done
    return 1
}

git_push_reason() {
    local protected_re="$1" cwd="${2:-.}"
    [ "$PROG" = git ] || return 1
    local -a a=("${ARGS[@]+"${ARGS[@]}"}")
    local i=0 sub=""
    while [ "$i" -lt "${#a[@]}" ]; do
        case "${a[$i]}" in
        -C | -c) i=$((i + 2)) ;;
        -*) i=$((i + 1)) ;;
        *)
            sub=${a[$i]}
            break
            ;;
        esac
    done
    [ "$sub" = push ] || return 1
    local -a rest=("${a[@]:$((i + 1))}") pos=()
    local w
    for w in "${rest[@]+"${rest[@]}"}"; do
        case "$w" in
        --all | --mirror)
            echo "git push $w would update the protected branch"
            return 0
            ;;
        -*) ;;
        *) pos+=("$w") ;;
        esac
    done
    local cur dst
    cur=$(git -C "$cwd" branch --show-current 2>/dev/null || true)
    if [ "${#pos[@]}" -le 1 ]; then
        if [[ $cur =~ ^(${protected_re})$ ]]; then
            echo "git push with no refspec would push the checked-out protected branch '$cur'"
            return 0
        fi
        return 1
    fi
    local k
    for ((k = 1; k < ${#pos[@]}; k++)); do
        dst=${pos[$k]#+}
        dst=${dst##*:}
        [ "$dst" = HEAD ] && dst=$cur
        dst=${dst#refs/heads/}
        if [[ $dst =~ ^(${protected_re})$ ]]; then
            echo "git push targets protected branch '$dst'"
            return 0
        fi
    done
    return 1
}
