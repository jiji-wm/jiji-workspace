# Completions for the jiji workspace ./scripts/build.sh and ./scripts/install.sh.
#
# Lives in conf.d (eager, sourced at shell startup) rather than completions/
# (autoloaded) because fish's completion autoloader only fires for commands
# resolvable in $PATH — a path-invoked `./scripts/build.sh` never triggers it.
# Once defined, fish matches `complete -c build.sh` against the *basename* of
# the typed command, so path invocations complete fine.
#
# Dynamic: candidates come from asking the script itself (`--targets`), so the
# target list has one home — scripts/project-targets.sh. Guards:
#   - token must be a path (bare `build.sh` from $PATH is not this script)
#   - script must be executable AND mention --targets in its text, so a
#     foreign build.sh is never executed by the completion (a script that
#     ignores unknown flags could otherwise start a real build).
#   - first positional only (token-count condition, not seen-subcommand).
# `-f` is scoped to the guarded rules — a foreign build.sh keeps normal
# file completion.

function __jiji_build_script_wants_target
    set -l tokens (commandline -opc)
    test (count $tokens) -eq 1; or return 1
    string match -q '*/*' -- $tokens[1]; or return 1
    test -x $tokens[1]; or return 1
    command grep -qs -- '--targets' $tokens[1]
end

function __jiji_build_script_targets
    set -l tok (commandline -opc)[1]
    command $tok --targets 2>/dev/null
end

for cmd in build.sh install.sh
    complete -c $cmd -f -n __jiji_build_script_wants_target \
        -a '(__jiji_build_script_targets)' -d 'project'
    complete -c $cmd -f -n __jiji_build_script_wants_target \
        -l targets -d 'List targets (one per line)'
end
