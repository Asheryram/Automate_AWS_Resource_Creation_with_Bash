#!/usr/bin/env bash

###############################################
# lib/state.sh
# State management setup utilities
###############################################

set -euo pipefail

# init_state: Initialize and pull state (combines state_init + state_pull)
# Usage: init_state
init_state() {
    state_init
    state_pull
}
