# Export the tenant configuration to compilers and receipt verification.
load_web_project_environment() {
    local allexport_was_set=0
    [[ $- != *a* ]] || allexport_was_set=1
    unset CLOUDFLARE_PROJECT_NAME DOMAIN
    set -a
    # shellcheck source=/dev/null
    source "$1"
    if [ "$allexport_was_set" -eq 0 ]; then
        set +a
    fi
}
