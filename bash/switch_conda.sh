#!/bin/bash

# Script: conda-switch.sh
# Description: Switch between two predefined Anaconda installations
# Usage: ./conda-switch.sh [1|2|status]
# This script was created with "Qwen/Qwen3-Coder-30B-A3B-Instruct" based on the prompt "Write a shell script that switches between two predefined anaconda installations on linux."

# Configuration - Set your Anaconda installation paths here
ANACONDA_PATH_1="/cluster/home/$USER/miniforge3"
ANACONDA_PATH_2="/cluster/projects/itea_lille-nv-fys-tem/miniforge3"

# Configuration - Set the name of your conda environment (optional)
ENV_NAME="base"

# Function to display usage
usage() {
    echo "Usage: $0 [1|2|status|help]"
    echo "  1        Switch to Anaconda installation 1"
    echo "  2        Switch to Anaconda installation 2"
    echo "  status   Show current active conda installation"
    echo "  help     Display this help message"
    exit 1
}

# Function to check if path exists
check_path() {
    local path="$1"
    if [[ ! -d "$path" ]]; then
        echo "Error: Path '$path' does not exist or is not a directory"
        return 1
    fi
    return 0
}

# Function to activate conda environment
activate_conda() {
    local conda_path="$1"
    local env_name="$2"
    
    # Check if conda is available
    if [[ ! -f "$conda_path/bin/conda" ]]; then
        echo "Error: Conda not found in $conda_path"
        return 1
    fi
    
    # Initialize conda for bash
    eval "$($conda_path/bin/conda shell.bash hook 2>/dev/null)"
    
    # Activate base environment if specified
    if [[ -n "$env_name" && "$env_name" != "base" ]]; then
        conda activate "$env_name" 2>/dev/null || echo "Warning: Could not activate environment '$env_name'"
    elif [[ -n "$env_name" ]]; then
        conda activate base 2>/dev/null || echo "Warning: Could not activate base environment"
    fi
    
    echo "Successfully activated conda from: $conda_path"
    return 0
}

# Function to get current conda path
get_current_conda() {
    if command -v conda &> /dev/null; then
        conda_info=$(conda info --base 2>/dev/null)
        if [[ -n "$conda_info" ]]; then
            echo "$conda_info"
        else
            echo "Unknown"
        fi
    else
        echo "None"
    fi
}

# Function to show current status
show_status() {
    echo "=== Conda Switch Status ==="
    echo "Installation 1: $ANACONDA_PATH_1"
    echo "Installation 2: $ANACONDA_PATH_2"
    echo ""
    echo "Current active conda installation:"
    current=$(get_current_conda)
    if [[ "$current" == "None" ]]; then
        echo "No conda installation currently active"
    elif [[ "$current" == *"Unknown"* ]]; then
        echo "$current"
    else
        echo "$current"
    fi
    echo ""
    
    # Check which installation we're using based on PATH
    if [[ ":$PATH:" == *":$ANACONDA_PATH_1/bin:"* ]]; then
        echo "Currently using: Installation 1 ($ANACONDA_PATH_1)"
    elif [[ ":$PATH:" == *":$ANACONDA_PATH_2/bin:"* ]]; then
        echo "Currently using: Installation 2 ($ANACONDA_PATH_2)"
    else
        echo "Using system Python/conda or unknown installation"
    fi
}

# Function to switch to conda installation 1
switch_to_1() {
    echo "Switching to Anaconda installation 1: $ANACONDA_PATH_1"
    
    if ! check_path "$ANACONDA_PATH_1"; then
        echo "Error: Installation 1 path does not exist"
        exit 1
    fi
    
    # Remove existing conda paths from PATH
    export PATH=$(echo "$PATH" | sed "s|$ANACONDA_PATH_2/bin:||g" | sed "s|:$ANACONDA_PATH_2/bin||g")
    
    # Add new conda path to beginning of PATH
    export PATH="$ANACONDA_PATH_1/bin:$PATH"
    
    # Activate the conda environment
    if ! activate_conda "$ANACONDA_PATH_1" "$ENV_NAME"; then
        echo "Warning: Could not properly activate conda from installation 1"
    fi
    
    echo "Switched to Anaconda 1 successfully!"
    echo "New PATH: $PATH"
}

# Function to switch to conda installation 2
switch_to_2() {
    echo "Switching to Anaconda installation 2: $ANACONDA_PATH_2"
    
    if ! check_path "$ANACONDA_PATH_2"; then
        echo "Error: Installation 2 path does not exist"
        exit 1
    fi
    
    # Remove existing conda paths from PATH
    export PATH=$(echo "$PATH" | sed "s|$ANACONDA_PATH_1/bin:||g" | sed "s|:$ANACONDA_PATH_1/bin||g")
    
    # Add new conda path to beginning of PATH
    export PATH="$ANACONDA_PATH_2/bin:$PATH"
    
    # Activate the conda environment
    if ! activate_conda "$ANACONDA_PATH_2" "$ENV_NAME"; then
        echo "Warning: Could not properly activate conda from installation 2"
    fi
    
    echo "Switched to Anaconda 2 successfully!"
    echo "New PATH: $PATH"
}

# Main script logic
case "${1:-status}" in
    1)
        switch_to_1
        ;;
    2)
        switch_to_2
        ;;
    status)
        show_status
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "Invalid option: $1"
        usage
        ;;
esac

# Export PATH so it persists in subshells
#export PATH