# Fish completions for the `workspace` command.

function __workspace_subcmd
    set -l tokens (commandline -opc)
    set -e tokens[1]
    for t in $tokens
        switch $t
            case '-*'
                continue
            case '*'
                echo $t
                return
        end
    end
    return 1
end

function __workspace_needs_sub
    not __workspace_subcmd >/dev/null 2>&1
end

function __workspace_groups
    workspace groups 2>/dev/null | awk 'NR>1 && /^\s/ {print $1}'
end

function __workspace_repos
    workspace list 2>/dev/null | awk 'NR>3 && /^\s/ {print $2}'
end

function __workspace_sources
    workspace list 2>/dev/null | awk 'NR>3 && /^\s/ {print $4}' | sort -u
end

function __workspace_csv --argument-names candidates
    set -l tokens (commandline -opc)
    set -l last $tokens[-1]
    set -l prefix (string replace -r ',[^,]*$' ',' -- $last 2>/dev/null; or echo '')
    set -l already (string split ',' -- $last)
    for c in (string split ' ' -- $candidates)
        contains -- $c $already; and continue
        echo "$prefix$c"
    end
end

function __workspace_subcmd_accepts_repos
    set -l sub (__workspace_subcmd); or return 1
    contains -- $sub clone status fetch pull sync dirty unpushed behind branches paths list cdr cdrepo
end

function __workspace_subcmd_accepts_workspace_name
    set -l sub (__workspace_subcmd); or return 1
    contains -- $sub root
end

function __workspace_at_shell_command
    set -l sub (__workspace_subcmd); or return 1
    contains -- $sub exec
end

function __workspace_at_strip_review_needed
    set -l sub (__workspace_subcmd); or return 1
    test "$sub" = strip-review-needed
end

complete -c workspace -f

complete -c workspace -f -n __workspace_needs_sub -a clone     -d 'Clone repos not yet present'
complete -c workspace -f -n __workspace_needs_sub -a status    -d 'Branch and working-tree status'
complete -c workspace -f -n __workspace_needs_sub -a fetch     -d 'Fetch all remotes'
complete -c workspace -f -n __workspace_needs_sub -a pull      -d 'Pull current branch'
complete -c workspace -f -n __workspace_needs_sub -a sync      -d 'Fetch + fast-forward every local branch'
complete -c workspace -f -n __workspace_needs_sub -a dirty     -d 'List repos with uncommitted changes'
complete -c workspace -f -n __workspace_needs_sub -a unpushed  -d 'List repos ahead of @{upstream}'
complete -c workspace -f -n __workspace_needs_sub -a behind    -d 'List repos behind @{upstream}'
complete -c workspace -f -n __workspace_needs_sub -a branches  -d 'Show current branch of each repo'
complete -c workspace -f -n __workspace_needs_sub -a exec      -d 'Run a shell command in each repo'
complete -c workspace -f -n __workspace_needs_sub -a list      -d 'List repos matching current filters'
complete -c workspace -f -n __workspace_needs_sub -a groups    -d 'List groups with repo counts'
complete -c workspace -f -n __workspace_needs_sub -a help      -d 'Show help'
complete -c workspace -f -n __workspace_needs_sub -a cdr       -d 'cd into a repo (in-shell, fish only)'
complete -c workspace -f -n __workspace_needs_sub -a cdrepo    -d 'cd into a repo (synonym for cdr)'
complete -c workspace -f -n __workspace_needs_sub -a root      -d 'cd to workspace root (in-shell, fish only)'
complete -c workspace -f -n __workspace_needs_sub -a strip-review-needed -d 'Strip Review-Needed: trailers'

complete -c workspace -s g -l group -x \
    -d 'Filter by group(s), comma-separated' \
    -a '(__workspace_csv (__workspace_groups))'

complete -c workspace -s s -l source -x \
    -d 'Filter by source(s), comma-separated' \
    -a '(__workspace_csv (__workspace_sources))'

complete -c workspace -s w -l workspace -x \
    -d 'Workspace to scope cdr to (registry name)' \
    -a '(__cdr_workspaces | string split -f1 "|")'

complete -c workspace -s h -l help -d 'Show help'

complete -c workspace -f -n __workspace_subcmd_accepts_repos \
    -a '(__workspace_repos)' -d 'repo path'

complete -c workspace -f -n __workspace_subcmd_accepts_workspace_name \
    -a '(__cdr_workspaces | string split -f1 "|")' \
    -d 'workspace name'

complete -c workspace -n __workspace_at_shell_command \
    -a '(__fish_complete_command)'

complete -c workspace -f -n __workspace_at_strip_review_needed \
    -l here    -d 'Run only in the current sub-repo (cwd)'
complete -c workspace -f -n __workspace_at_strip_review_needed \
    -l apply   -d 'Actually rewrite (default is preview)'
complete -c workspace -f -n __workspace_at_strip_review_needed \
    -l force   -d 'Allow rewriting commits already pushed to upstream'
