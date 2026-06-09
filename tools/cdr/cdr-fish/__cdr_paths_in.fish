function __cdr_paths_in --argument-names ws_root rel_prefix \
    --description "Internal: print abs repo paths from one workspace's repos.conf"
    test -f "$ws_root/repos.conf"; or return 0
    awk -F'|' -v root="$ws_root" -v rel="$rel_prefix" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        NF >= 2 {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            if ($1 == "") next
            printf "%s/%s%s/%s\n", root, rel, $1, $2
        }
    ' "$ws_root/repos.conf"
end
