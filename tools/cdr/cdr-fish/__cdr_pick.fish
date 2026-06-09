function __cdr_pick --description "Internal: filter to existing dirs, fzf-pick, cd"
    set -l existing
    while read -l p
        test -d "$p"; and set -a existing $p
    end
    test (count $existing) -eq 0; and return 1
    set -l choice (printf '%s\n' $existing | \
        fzf --reverse --height=40% --select-1 --exit-0 --scheme=path --query="$argv")
    test -n "$choice"; and cd "$choice"
end
