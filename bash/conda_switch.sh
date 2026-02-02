#!/bin/bash

# Script: auto-conda-switch.sh
# Description: Automatically detect and switch between all conda installations
# Usage: ./auto-conda-switch.sh [list|switch|status|help]
# Created by "Qwen/Qwen3-Coder-30B-A3B-Instruct".

# Global variables
INSTALLATIONS=()
INSTALLATION_NAMES=()

# Function to display usage
usage() {
    echo "Usage: $0 [list|switch|status|help]"
    echo "  list     List all detected conda installations"
    echo "  switch   Interactive switch between installations"
    echo "  status   Show current active conda installation"
    echo "  help     Display this help message"
    exit 1
}

# Function to find conda installations
find_conda_installations() {
    INSTALLATIONS=()
    INSTALLATION_NAMES=()
    
    echo "Searching for conda installations..."
    
    # Common locations where conda installations might be found
    common_paths=(
        "/opt/anaconda3"
        "/opt/miniconda3"
        "/opt/miniforge3"
        "/usr/local/anaconda3"
        "/usr/local/miniconda3"
        "/usr/local/miniforge3"
        "$HOME/anaconda3"
        "$HOME/miniconda3"
        "$HOME/miniforge3"
        "$HOME/.conda/envs"
        "/opt/conda"
        "/usr/local/conda"
    )
    
    # Search in common user directories
    user_dirs=(
        "$HOME"
        "$HOME/opt"
        "$HOME/software"
        "$HOME/apps"
        "$HOME/local"
        "/cluster/home/$USER/"
        "/cluster/projects/itea_lille-nv-fys-tem/"
    )

    # Find installations in common paths
    for path in "${common_paths[@]}"; do
        if [[ -d "$path" && -f "$path/bin/conda" ]]; then
            INSTALLATIONS+=("$path")
            INSTALLATION_NAMES+=("$(basename "$path")")
            echo "Found: $path"
        fi
    done
    
    # Search in user directories recursively
    for user_dir in "${user_dirs[@]}"; do
        if [[ -d "$user_dir" ]]; then
            while IFS= read -r -d '' dir; do
                if [[ -f "$dir/bin/conda" ]]; then
                    # Avoid duplicates
                    if ! [[ " ${INSTALLATIONS[*]} " =~ " $dir " ]]; then
                        INSTALLATIONS+=("$dir")
                        INSTALLATION_NAMES+=("$(basename "$dir")")
                        echo "Found: $dir"
                    fi
                fi
            done < <(find "$user_dir" -type d -name "conda*" -o -name "miniconda*" -o -name "miniforge*" -print0 2>/dev/null)
        fi
    done
    
    # Also check PATH for conda executables
    while IFS= read -r conda_path; do
        if [[ -n "$conda_path" && -f "$conda_path" ]]; then
            # Get the parent directory (installation root)
            conda_dir=$(dirname "$(dirname "$conda_path")")
            if [[ -d "$conda_dir" && -f "$conda_dir/bin/conda" ]]; then
                # Avoid duplicates
                if ! [[ " ${INSTALLATIONS[*]} " =~ " $conda_dir " ]]; then
                    INSTALLATIONS+=("$conda_dir")
                    INSTALLATION_NAMES+=("$(basename "$conda_dir")")
                    echo "Found via PATH: $conda_dir"
                fi
            fi
        fi
    done < <(which -a conda 2>/dev/null)
    
    # Remove duplicates and empty entries
    declare -A seen
    filtered_installations=()
    filtered_names=()
    
    for i in "${!INSTALLATIONS[@]}"; do
        if [[ -n "${INSTALLATIONS[$i]}" ]] && [[ ! -z "${seen[${INSTALLATIONS[$i]}]}" ]]; then
            continue
        fi
        seen["${INSTALLATIONS[$i]}"]=1
        filtered_installations+=("${INSTALLATIONS[$i]}")
        filtered_names+=("${INSTALLATION_NAMES[$i]}")
    done
    
    INSTALLATIONS=("${filtered_installations[@]}")
    INSTALLATION_NAMES=("${filtered_names[@]}")
    
    echo "Total installations found: ${#INSTALLATIONS[@]}"
}

# Function to validate installation
validate_installation() {
    local path="$1"
    local name="$2"
    
    if [[ ! -d "$path" ]]; then
        return 1
    fi
    
    if [[ ! -f "$path/bin/conda" ]]; then
        return 1
    fi
    
    # Additional check - try to get conda info
    if ! "$path/bin/conda" --version >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Function to list all installations
list_installations() {
    echo "=== Detected Conda Installations ==="
    
    if [[ ${#INSTALLATIONS[@]} -eq 0 ]]; then
        echo "No conda installations found."
        return
    fi
    
    for i in "${!INSTALLATIONS[@]}"; do
        path="${INSTALLATIONS[$i]}"
        name="${INSTALLATION_NAMES[$i]}"
        
        # Validate installation
        if validate_installation "$path" "$name"; then
            echo "$((i+1)). $name"
            echo "   Path: $path"
            
            # Try to get version info
            if "$path/bin/conda" --version >/dev/null 2>&1; then
                version=$("$path/bin/conda" --version 2>&1 | head -1)
                echo "   Version: $version"
            fi
            
            # Check if it's miniforge (has mamba)
            if [[ -f "$path/bin/mamba" ]]; then
                echo "   Type: Miniforge (with Mamba)"
            elif [[ -f "$path/bin/conda-meta" ]]; then
                echo "   Type: Standard Conda"
            fi
            
            echo ""
        else
            echo "$((i+1)). $name (INVALID - missing conda binary)"
            echo "   Path: $path"
            echo ""
        fi
    done
}

# Function to get current conda installation
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
    echo "=== Current System Status ==="
    
    # Show current active installation
    current=$(get_current_conda)
    echo "Active conda installation:"
    if [[ "$current" == "None" ]]; then
        echo "  No conda installation active"
    else
        echo "  $current"
    fi
    
    # Show PATH info
    echo ""
    echo "PATH contains conda paths:"
    echo "$PATH" | tr ':' '\n' | grep -E "(anaconda|miniconda|miniforge)" | head -5
    
    echo ""
    echo "Available installations:"
    if [[ ${#INSTALLATIONS[@]} -eq 0 ]]; then
        echo "  None found"
    else
        for i in "${!INSTALLATIONS[@]}"; do
            path="${INSTALLATIONS[$i]}"
            name="${INSTALLATION_NAMES[$i]}"
            if validate_installation "$path" "$name"; then
                echo "  $((i+1)). $name ($path)"
            fi
        done
    fi
}

# Function to interactively switch installations
interactive_switch() {
    if [[ ${#INSTALLATIONS[@]} -eq 0 ]]; then
        echo "No conda installations found to switch to."
        return
    fi
    
    echo "=== Switch to Conda Installation ==="
    list_installations
    
    echo ""
    echo "Enter the number of the installation to switch to (or 'q' to quit):"
    
    read -r choice
    
    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        echo "Switch cancelled."
        return
    fi
    
    # Validate choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#INSTALLATIONS[@]} ]]; then
        echo "Invalid selection: $choice"
        return
    fi
    
    # Switch to selected installation
    selected_index=$((choice - 1))
    selected_path="${INSTALLATIONS[$selected_index]}"
    selected_name="${INSTALLATION_NAMES[$selected_index]}"
    
    echo "Switching to $selected_name at $selected_path..."
    
    # Clean up existing conda paths
    cleanup_paths
    
    # Add new conda path
    add_to_path "$selected_path"
    
    # Initialize and activate
    initialize_conda "$selected_path"
    
    echo "Successfully switched to $selected_name!"
    echo "Current PATH prefix: $(echo $PATH | cut -d':' -f1-3)"
}

# Function to safely remove conda paths from PATH
cleanup_paths() {
    # Remove all conda installations from PATH
    local cleaned_path=""
    for path_segment in $(echo "$PATH" | tr ':' '\n'); do
        if [[ ! "$path_segment" =~ /(anaconda|miniconda|miniforge)/ ]]; then
            if [[ -z "$cleaned_path" ]]; then
                cleaned_path="$path_segment"
            else
                cleaned_path="$cleaned_path:$path_segment"
            fi
        fi
    done
    export PATH="$cleaned_path"
}

# Function to add conda path to PATH
add_to_path() {
    local conda_path="$1"
    # Add to beginning of PATH to ensure priority
    export PATH="$conda_path/bin:$PATH"
}

# Function to initialize conda for bash
initialize_conda() {
    local conda_path="$1"
    
    # Try different initialization methods for compatibility
    if [[ -f "$conda_path/etc/profile.d/conda.sh" ]]; then
        source "$conda_path/etc/profile.d/conda.sh"
    elif [[ -f "$conda_path/bin/conda" ]]; then
        eval "$($conda_path/bin/conda shell.bash hook 2>/dev/null)"
    fi
}

# Function to switch to specific installation by index
switch_to_installation() {
    local index="$1"
    
    if [[ ${#INSTALLATIONS[@]} -eq 0 ]]; then
        echo "No conda installations found."
        return 1
    fi
    
    if [[ "$index" -lt 1 ]] || [[ "$index" -gt ${#INSTALLATIONS[@]} ]]; then
        echo "Invalid installation number: $index"
        return 1
    fi
    
    selected_index=$((index - 1))
    selected_path="${INSTALLATIONS[$selected_index]}"
    selected_name="${INSTALLATION_NAMES[$selected_index]}"
    
    if ! validate_installation "$selected_path" "$selected_name"; then
        echo "Installation $selected_name is invalid."
        return 1
    fi
    
    echo "Switching to $selected_name at $selected_path..."
    
    # Clean up existing conda paths
    cleanup_paths
    
    # Add new conda path
    add_to_path "$selected_path"
    
    # Initialize and activate
    initialize_conda "$selected_path"
    
    echo "Successfully switched to $selected_name!"
    return 0
}

# Main script logic
case "${1:-status}" in
    list)
        find_conda_installations
        list_installations
        ;;
    switch)
        find_conda_installations
        interactive_switch
        ;;
    status)
        find_conda_installations
        show_status
        ;;
    help|-h|--help)
        usage
        ;;
    [0-9]*)
        # Handle direct number input (e.g., ./script.sh 1)
        find_conda_installations
        switch_to_installation "$1"
        ;;
    *)
        echo "Invalid option: $1"
        usage
        ;;
esac

# Export PATH so it persists in subshells
export PATH