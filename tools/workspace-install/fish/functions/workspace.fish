# Fish wrapper for the `workspace` command.
# Intercepts cwd-changing subcommands (cdr, cdrepo, root) so they can
# change the calling shell's directory. Everything else is delegated to
# the bash dispatcher via `command workspace`.

function workspace --description "Workspace dispatcher (cd subcommands handled in-shell)"
    if test (count $argv) -ge 1
        switch $argv[1]
            case cdr cdrepo
                set -l rest $argv[2..]
                set -l ws ""
                while test (count $rest) -ge 1
                    switch $rest[1]
                        case -w --workspace
                            if test (count $rest) -lt 2
                                echo "workspace $argv[1]: -w/--workspace needs a value" >&2
                                return 1
                            end
                            set ws $rest[2]
                            set rest $rest[3..]
                        case '*'
                            break
                    end
                end
                if test -n "$ws"
                    __cdr_paths_for $ws | __cdr_pick $rest
                else
                    __cdr_paths_for_all | __cdr_pick $rest
                end
                return
            case root
                __workspace_root_pick $argv[2..]
                return
        end
    end
    command workspace $argv
end
