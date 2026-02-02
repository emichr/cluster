#!/bin/bash

# Script: debug-conda-switch.sh
# Description: Debug version to find all conda installations with detailed logging
# Usage: ./debug-conda-switch.sh [list|switch|status|help|debug]

# Cluster-specific paths to search
CLUSTER_PATHS=(
    "/cluster/home/$USER/"
    "/cluster/projects/itea_lille-nv-fys-tem/"
    "/cluster/apps/anaconda3"
    "/cluster/apps/miniconda3"
    "/cluster/apps/miniforge3"
    "/cluster/software/anaconda3"
    "/cluster/software/miniconda3"
    "/cluster/software/miniforge3"
)

# Additional common paths for cluster environments
COMMON_CLUSTER_PATHS=(
    "/opt/anaconda3"
    "/opt/miniconda3"
    "/opt/miniforge3"
    "/usr/local/anaconda3"
    "/usr/local/miniconda3"
    "/usr/local/miniforge3"
)

# Global variables
INSTALLATIONS=()
INSTALLATION_NAMES=()

# Function to display usage
usage() {
    echo "Usage: $0 [list|switch|status|help|debug]"
    echo "  list     List all detected conda installations"
    echo "  switch   Interactive switch between installations"
    echo "  status   Show current active conda installation"
    echo "  help     Display this help message"
    echo "  debug    Debug mode - show detailed search process"
    exit 1
}

# Function to debug search process
debug_search() {
    echo "=== DEBUG MODE: Detailed Search Process ==="
    echo "User: $USER"
    echo "Home: $HOME"
    echo "Current working directory: $(pwd)"
    echo ""
    
    # Show all cluster paths being searched
    echo "Cluster paths being searched:"
    for i in "${!CLUSTER_PATHS[@]}"; do
        echo "  $((i+1)). ${CLUSTER_PATHS[$i]}"
    done
    echo ""
    
    # Show all common paths being searched
    echo "Common cluster paths being searched:"
    for i in "${!COMMON_CLUSTER_PATHS[@]}"; do
        echo "  $((i+1)). ${COMMON_CLUSTER_PATHS[$i]}"
    done
    echo ""
    
    # Check each cluster path individually
    echo "=== Checking Each Cluster Path ==="
    for path in "${CLUSTER_PATHS[@]}"; do
        echo "Checking: $path"
        if [[ -d "$path" ]]; then
            echo "  ✓ Directory exists"
            echo "  Contents:"
            ls -la "$path" 2>/dev/null | head -10
            echo ""
            
            # Look for conda installations in this directory
            echo "  Searching for conda installations in $path:"
            find "$path" -maxdepth 3 -type d \( -name "anaconda3" -o -name "miniconda3" -o -name "miniforge3" \) 2>/dev/null | while read -r conda_dir; do
                echo "    Found potential: $conda_dir"
                if [[ -f "$conda_dir/bin/conda" ]]; then
                    echo "    ✓ Valid conda installation found"
                    echo "    Version: $($conda_dir/bin/conda --version 2>&1)"
                else
                    echo "    ✗ No conda binary found"
                fi
            done
        else
            echo "  ✗ Directory does not exist"
        fi
        echo ""
    done
    
    # Check PATH for conda executables
    echo "=== Checking PATH for conda executables ==="
    echo "PATH: $PATH"
    echo ""
    echo "Conda executables found in PATH:"
    which -a conda 2>/dev/null | while read -r conda_path; do
        echo "  Found: $conda_path"
        if [[ -n "$conda_path" && -f "$conda_path" ]]; then
            conda_dir=$(dirname "$(dirname "$conda_path")")
            echo "  Installation root: $conda_dir"
            if [[ -f "$conda_dir/bin/conda" ]]; then
                echo "  ✓ Valid conda installation"
                echo "  Version: $($conda_dir/bin/conda --version 2>&1)"
            else
                echo "  ✗ Invalid installation root"
            fi
        fi
    done
    echo ""
}

# Function to find conda installations on cluster
find_conda_installations() {
    INSTALLATIONS=()
    INSTALLATION_NAMES=()
    
    echo "Searching for conda installations in cluster paths..."
    
    # Debug: Show what we're looking for
    echo "Looking for conda installations in these patterns:"
    echo "  - anaconda3"
    echo "  - miniconda3" 
    echo "  - miniforge3"
    echo ""
    
    # Search in cluster-specific paths first
    echo "Checking cluster paths..."
    for path in "${CLUSTER_PATHS[@]}"; do
        echo "Searching in: $path"
        if [[ -d "$path" ]]; then
            echo "  Directory exists"
            
            # Look for conda installations in this directory
            find "$path" -maxdepth 3 -type d \( -name "anaconda3" -o -name "miniconda3" -o -name "miniforge3" \) 2>/dev/null | while read -r conda_dir; do
                echo "  Found potential: $conda_dir"
                if [[ -f "$conda_dir/bin/conda" ]]; then
                    echo "  ✓ Valid conda installation found at: $conda_dir"
                    INSTALLATIONS+=("$conda_dir")
                    INSTALLATION_NAMES+=("$(basename "$conda_dir")")
                else
                    echo "  ✗ No conda binary at: $conda_dir"
                fi
            done
        else
            echo "  ✗ Directory does not exist: $path"
        fi
    done
    
    # Search in additional common cluster paths
    echo "Checking additional cluster paths..."
    for path in "${COMMON_CLUSTER_PATHS[@]}"; do
        echo "Checking: $path"
        if [[ -d "$path" && -f "$path/bin/conda" ]]; then
            echo "  ✓ Valid conda installation found: $path"
            INSTALLATIONS+=("$path")
            INSTALLATION_NAMES+=("$(basename "$path")")
        else
            if [[ -d "$path" ]]; then
                echo "  ✗ Directory exists but no conda binary at: $path"
                if [[ -f "$path/bin/conda" ]]; then
                    echo "    Actually found conda binary at: $path/bin/conda"
                fi
            else
                echo "  ✗ Directory does not exist: $path"
            fi
        fi
    done
    
    # Also check PATH for conda executables (cluster-specific)
    echo "Checking PATH for conda installations..."
    while IFS= read -r conda_path; do
        if [[ -n "$conda_path" && -f "$conda_path" ]]; then
            echo "Found conda in PATH: $conda_path"
            # Get the parent directory (installation root)
            conda_dir=$(dirname "$(dirname "$conda_path")")
            echo "Installation root: $conda_dir"
            if [[ -d "$conda_dir" && -f "$conda_dir/bin/conda" ]]; then
                # Avoid duplicates
                if ! [[ " ${INSTALLATIONS[*]} " =~ " $conda_dir " ]]; then
                    echo "  ✓ Adding to installations: $conda_dir"
                    INSTALLATIONS+=("$conda_dir")
                    INSTALLATION_NAMES+=("$(basename "$conda_dir")")
                else
                    echo "  ✓ Already found, skipping duplicate"
                fi
            else
                echo "  ✗ Invalid installation root: $conda_dir"
            fi
        fi
    done < <(which -a conda 2>/dev/null)
    
    # Remove duplicates and empty entries
    declare -A seen
    filtered_installations=()
    filtered_names=()
    
    echo "Before deduplication - Found ${#INSTALLATIONS[@]} installations:"
    for i in "${!INSTALLATIONS[@]}"; do
        echo "  $((i+1)). ${INSTALLATIONS[$i]} (${INSTALLATION_NAMES[$i]})"
    done
    
    for i in "${!INSTALLATIONS[@]}"; do
        if [[ -n "${INSTALLATIONS[$i]}" ]] && [[ ! -z "${seen[${INSTALLATIONS[$i]}]}" ]]; then
            echo "Skipping duplicate: ${INSTALLATIONS[$i]}"
            continue
        fi
        seen["${INSTALLATIONS[$i]}"]=1
        filtered_installations+=("${INSTALLATIONS[$i]}")
        filtered_names+=("${INSTALLATION_NAMES[$i]}")
        echo "Keeping: ${INSTALLATIONS[$i]} (${INSTALLATION_NAMES[$i]})"
    done
    
    INSTALLATIONS=("${filtered_installations[@]}")
    INSTALLATION_NAMES=("${filtered_names[@]}")
    
    echo "After deduplication - Final count: ${#INSTALLATIONS[@]}"
    
    # Validate each installation
    echo "Validating installations:"
    for i in "${!INSTALLATIONS[@]}"; do
        path="${INSTALLATIONS[$i]}"
        name="${INSTALLATION_NAMES[$i]}"
        echo "  Checking $name at $path..."
        if validate_installation "$path" "$name"; then
            echo "    ✓ Valid"
        else
            echo "    ✗ Invalid - removing"
            # Remove invalid installation
            INSTALLATIONS=("${INSTALLATIONS[@]:0:$i}" "${INSTALLATIONS[@]:$((i+1))}")
            INSTALLATION_NAMES=("${INSTALLATION_NAMES[@]:0:$i}" "${INSTALLATION_NAMES[@]:$((i+1))}")
        fi
    done
    
    echo "Final installations found: ${#INSTALLATIONS[@]}"
}

# Function to validate installation
validate_installation() {
    local path="$1"
    local name="$2"
    
    echo "  Validating: $path"
    
    if [[ ! -d "$path" ]]; then
        echo "    ✗ Directory does not exist"
        return 1
    fi
    
    if [[ ! -f "$path/bin/conda" ]]; then
        echo "    ✗ No conda binary found at $path/bin/conda"
        return 1
    fi
    
    # Additional check - try to get conda info
    if ! "$path/bin/conda" --version >/dev/null 2>&1; then
        echo "    ✗ Conda version check failed"
        return 1
    fi
    
    echo "    ✓ Installation is valid"
    return 0
}

# Function to list all installations
list_installations() {
    echo "=== Detected Conda Installations on Cluster ==="
    
    if [[ ${#INSTALLATIONS[@]} -eq 0 ]]; then
        echo "No conda installations found on cluster."
        echo "This might be due to:"
        echo "  1. No installations in the searched directories"
        echo "  2. Insufficient permissions to access directories"
        echo "  3. Installations don't follow expected naming patterns"
        echo "  4. Conda binary not found in expected location"
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
            
            # Show cluster location info
            if [[ "$path" == "/cluster/"* ]]; then
                echo "   Location: Cluster storage"
            elif [[ "$path" == "$HOME/"* ]]; then
                echo "   Location: User home directory"
            elif [[ "$path" == "/opt/"* ]] || [[ "$path" == "/usr/local/"* ]]; then
                echo "   Location: System-wide installation"
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
    echo "=== Current Cluster System Status ==="
    
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
    echo "$PATH" | tr ':' '\n' | grep -E "(anaconda|miniconda|miniforge|cluster)" | head -5
    
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
    
    # Show cluster-specific info
    echo ""
    echo "Cluster Environment Info:"
    echo "  User: $USER"
    echo "  Home directory: $HOME"
    echo "  Cluster paths being searched:"
    for path in "${CLUSTER_PATHS[@]}"; do
        echo "    $path"
    done
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
    debug)
        debug_search
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