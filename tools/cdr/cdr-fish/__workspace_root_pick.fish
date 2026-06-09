function __workspace_root_pick --description "Internal: cd to a workspace root (walk-up or fzf)"
    if test (count $argv) -ge 1
        for entry in (__cdr_workspaces)
            set -l parts (string split '|' -- $entry)
            test (count $parts) -ge 2; or continue
            if test "$parts[1]" = "$argv[1]"
                cd "$parts[2]"
                return
            end
        end
        set -l roots
        for entry in (__cdr_workspaces)
            set -l parts (string split '|' -- $entry)
            test (count $parts) -ge 2; or continue
            set -a roots "$parts[2]"
        end
        test (count $roots) -eq 0; and return 1
        set -l choice (printf '%s\n' $roots | \
            fzf --reverse --height=40% --select-1 --exit-0 \
                --scheme=path --query="$argv[1]")
        test -n "$choice"; and cd "$choice"
        return
    end
    set -l dir $PWD
    while test "$dir" != "/"
        for entry in (__cdr_workspaces)
            set -l parts (string split '|' -- $entry)
            test (count $parts) -ge 2; or continue
            if test "$parts[2]" = "$dir"
                cd "$dir"
                return
            end
        end
        set dir (dirname "$dir")
    end
    set -l roots
    for entry in (__cdr_workspaces)
        set -l parts (string split '|' -- $entry)
        test (count $parts) -ge 2; or continue
        set -a roots "$parts[2]"
    end
    test (count $roots) -eq 0; and return 1
    set -l choice (printf '%s\n' $roots | \
        fzf --reverse --height=40% --select-1 --exit-0 --scheme=path)
    test -n "$choice"; and cd "$choice"
end
