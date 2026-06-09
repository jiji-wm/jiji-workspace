function __cdr_paths_for_all --description "Internal: print abs repo paths from every registered workspace"
    for entry in (__cdr_workspaces)
        set -l parts (string split '|' -- $entry)
        test (count $parts) -ge 2; or continue
        set -l prefix ""
        test (count $parts) -ge 3; and set prefix $parts[3]
        __cdr_paths_in $parts[2] $prefix
    end
end
