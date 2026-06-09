function __cdr_workspaces --description "Print registered workspaces (name|root|prefix per line)"
    set -l registry "$HOME/.config/cdr/workspaces.conf"
    test -f "$registry"; or return 0
    while read -l line
        test -z "$line"; and continue
        string match -q '#*' -- "$line"; and continue
        echo "$line"
    end < "$registry"
end
