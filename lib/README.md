# lib/ — Modular Utility Library

This directory contains reusable, single-responsibility shell modules following Unix philosophy: "Do one thing and do it well."

## Module Overview

| Module | Purpose | Functions |
|--------|---------|-----------|
| **args.sh** | CLI argument parsing | `parse_dry_run_flag()` |
| **checks.sh** | Dependency/credential verification | `check_command()`, `check_aws_credentials()`, `check_dependencies()` |
| **prompts.sh** | User input collection | `prompt_cidr()`, `get_cidr_or_env()` |
| **output.sh** | Formatting and logging output | `print_header()`, `print_footer()`, `print_dryrun_*()`, `exit_dryrun()` |
| **state.sh** | State management setup | `init_state()` |

## Usage

Import only the modules you need in each script:

```bash
# In a create script
source "${SCRIPT_DIR}/lib/args.sh"
source "${SCRIPT_DIR}/lib/checks.sh"
source "${SCRIPT_DIR}/lib/prompts.sh"
source "${SCRIPT_DIR}/lib/output.sh"
source "${SCRIPT_DIR}/lib/state.sh"

# In cleanup script
source "${SCRIPT_DIR}/lib/args.sh"
source "${SCRIPT_DIR}/lib/checks.sh"
source "${SCRIPT_DIR}/lib/output.sh"
source "${SCRIPT_DIR}/lib/state.sh"
```

## Benefits

- **Modularity**: Each file focuses on one aspect
- **Reusability**: Functions used by multiple scripts
- **Maintainability**: Changes to argument parsing only affect `args.sh`
- **Testability**: Smaller modules easier to unit test
- **Clarity**: Clear separation of concerns

## Example: Adding a new prompt

To add a new prompt function, add it to `prompts.sh`:

```bash
# prompt_instance_type: Prompt for EC2 instance type
prompt_instance_type() {
    local instance_type=""
    read -rp "Enter EC2 instance type (e.g., t3.micro, t3.small): " instance_type
    while [[ -z "$instance_type" ]]; do
        log_error "Instance type cannot be empty"
        read -rp "Enter EC2 instance type: " instance_type
    done
    echo "$instance_type"
}
```

Then use it in any script:
```bash
INSTANCE_TYPE=$(prompt_instance_type)
```
