#!/usr/bin/env bash

###############################################
# lib/args.sh
# Argument parsing utilities
###############################################

set -euo pipefail

# parse_dry_run_flag: Extract --dry-run and -y/--yes from args
# Usage: parse_dry_run_flag "$@"
parse_dry_run_flag() {
    DRY_RUN="false"
    AUTO_CONFIRM="false"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|--dry)
                DRY_RUN="true"
                shift
                ;;
            -y|--yes)
                AUTO_CONFIRM="true"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--dry-run] [-y|--yes]"
                echo "  --dry-run, --dry   Preview actions without making changes"
                echo "  -y, --yes          Skip confirmation prompts"
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done
    export DRY_RUN
    export AUTO_CONFIRM
}
