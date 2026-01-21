#!/usr/bin/env bash

###############################################
# lib/args.sh
# Argument parsing utilities
###############################################

set -euo pipefail

# parse_dry_run_flag: Extract --dry-run from args and set DRY_RUN variable
# Usage: parse_dry_run_flag "$@"
parse_dry_run_flag() {
    DRY_RUN="false"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|--dry)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--dry-run]"
                echo "  --dry-run, --dry   Preview actions without making changes"
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done
    export DRY_RUN
}
