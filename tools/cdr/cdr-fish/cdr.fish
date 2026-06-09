# Top-level alias for `workspace cdr`. Canonical implementation lives in
# tools/workspace-install/fish/functions/workspace.fish.
function cdr --description "Fuzzy cd into a repo from any registered workspace"
    workspace cdr $argv
end
