#!/usr/bin/env bash

###############################################
# lib/output.sh
# Logging, formatting, and output utilities
###############################################

set -euo pipefail

# print_header: Print a standard section header
# Usage: print_header "Creating Resources"
print_header() {
    local title="$1"
    log_info "=========================================="
    log_info "$title"
    log_info "=========================================="
}

# print_footer: Print a standard section footer
# Usage: print_footer "Operation Complete"
print_footer() {
    local title="$1"
    log_info "=========================================="
    log_info "$title"
    log_info "=========================================="
}

# print_dryrun_header: Print dry-run header
print_dryrun_header() {
    log_dryrun ""
    log_dryrun "==================== DRY-RUN ===================="
}

# print_dryrun_footer: Print dry-run footer
print_dryrun_footer() {
    log_dryrun "=================================================="
    log_dryrun "No resources will be created in dry-run mode."
}

# exit_dryrun: Exit cleanly after dry-run display
exit_dryrun() {
    print_dryrun_footer
    exit 0
}

# print_dry_run_notice: Print standard dry-run notice at startup
# Usage: [[ "$DRY_RUN" == "true" ]] && print_dry_run_notice
print_dry_run_notice() {
    log_warn "DRY-RUN MODE ENABLED"
}
