function __cdr_paths_for --argument-names name \
    --description "Internal: print abs repo paths for the named registered workspace"
    for entry in (__cdr_workspaces)
        set -l parts (string split '|' -- $entry)
        test (count $parts) -ge 2; or continue
        if test "$parts[1]" = "$name"
            set -l prefix ""
            test (count $parts) -ge 3; and set prefix $parts[3]
            __cdr_paths_in $parts[2] $prefix
            return
        end
    end
    echo "cdr: workspace '$name' not registered (see ~/.config/cdr/workspaces.conf)" >&2
    return 1
end
