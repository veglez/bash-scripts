#!/usr/bin/env bash
#
# folder_summary.sh - Generate a summary of files in a specified folder
#
# This script creates a consolidated view of file contents within a directory,
# with support for pattern-based filtering and multiple output modes.

# Enable strict error handling
set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_VERSION="2.1.0"

# Default configuration
readonly DEFAULT_OUTPUT_MODE="cli"
readonly SUMMARY_FILENAME="folder_summary.txt"
readonly DEFAULT_EXCLUDE_HIDDEN=true

# Initialize variables
folder_path=""
output_mode="${DEFAULT_OUTPUT_MODE}"
declare -a include_patterns=()
declare -a exclude_patterns=()
use_include_filter=false
use_exclude_filter=false
exclude_hidden="${DEFAULT_EXCLUDE_HIDDEN}"
include_summary=false

# Statistics for summary
declare -A file_extensions
declare -A file_sizes
total_size=0
largest_file=""
largest_file_size=0

# Color codes for better CLI output (disabled if not interactive)
if [[ -t 1 ]]; then
    readonly COLOR_ERROR='\033[0;31m'
    readonly COLOR_SUCCESS='\033[0;32m'
    readonly COLOR_INFO='\033[0;36m'
    readonly COLOR_RESET='\033[0m'
else
    readonly COLOR_ERROR=''
    readonly COLOR_SUCCESS=''
    readonly COLOR_INFO=''
    readonly COLOR_RESET=''
fi

# Function to display error messages
error() {
    echo -e "${COLOR_ERROR}Error: $*${COLOR_RESET}" >&2
}

# Function to display success messages
success() {
    echo -e "${COLOR_SUCCESS}$*${COLOR_RESET}"
}

# Function to display info messages
info() {
    echo -e "${COLOR_INFO}$*${COLOR_RESET}"
}

# Function to display usage information
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} <folder_path> [OPTIONS]

Options:
    -h, --help                          Show this help message
    -i, --include PATTERNS              Comma-separated list of patterns to include
    -e, --exclude PATTERNS              Comma-separated list of patterns to exclude
    -o, --output MODE                   Output mode: 'cli' (default) or 'file'
    -H, --include-hidden                Include hidden files and directories
    -s, --include-summary               Include a summary at the end
    -v, --version                       Show version information

Examples:
    ${SCRIPT_NAME} /path/to/folder
    ${SCRIPT_NAME} /path/to/folder --include '*.py,*.sh' --output file
    ${SCRIPT_NAME} /path/to/folder --exclude 'node_modules,*.log'
    ${SCRIPT_NAME} /path/to/folder --include-hidden --exclude '.git/*'
    ${SCRIPT_NAME} /path/to/folder --include-summary

EOF
}

# Function to display detailed help information
help_message() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - Generate a summary of files in a specified folder

DESCRIPTION:
    This script generates a comprehensive summary of files in the specified folder.
    By default, it includes all files (excluding '${SUMMARY_FILENAME}' if present)
    and outputs to the command line. You can filter files using include/exclude
    patterns and choose between CLI or file output.

PATTERN MATCHING:
    Patterns support both glob-style wildcards and regular expressions:
    - Glob patterns: *.txt, test_*, file.??
    - Regex patterns: .*\\.py$, ^src/.*
    - Path patterns: src/*.js, **/test/*
    
    Hidden files behavior:
    - Hidden files/directories are excluded by default
    - Use --include-hidden to include ALL hidden files
    - Use --include '.pattern' to include specific hidden files
    - Exclude patterns work on hidden files when --include-hidden is used

OPTIONS:
    <folder_path>
        Required. The path to the folder to summarize.

    -i, --include PATTERNS
    --just-include PATTERNS (deprecated)
        Optional. Comma-separated list of patterns. Only files matching
        these patterns will be included in the summary.

    -e, --exclude PATTERNS
        Optional. Comma-separated list of patterns. Files matching these
        patterns will be excluded from the summary.

    -o, --output MODE
        Optional. Output destination:
        - 'cli': Display on command line (default)
        - 'file': Save to '${SUMMARY_FILENAME}' in the target folder

    -H, --include-hidden
        Optional. Include hidden files and directories (those starting with .).
        By default, hidden files are excluded unless explicitly matched by
        an include pattern.

    -s, --include-summary
        Optional. Generate and display a summary at the end with statistics
        about processed files, including file counts by extension, total size,
        and largest files.

    -v, --version
        Display version information.

    -h, --help
        Display this help message.

EXAMPLES:
    Basic usage:
        ${SCRIPT_NAME} /home/user/project

    Include only Python and shell scripts:
        ${SCRIPT_NAME} /home/user/project --include '*.py,*.sh'

    Include all files including hidden:
        ${SCRIPT_NAME} /home/user/project --include-hidden
        
    Include specific hidden files without --include-hidden:
        ${SCRIPT_NAME} /home/user/project --include '.bashrc,.gitignore'

    Exclude .git but include other hidden files:
        ${SCRIPT_NAME} /home/user/project --include-hidden --exclude '.git/*'

    Generate with summary statistics:
        ${SCRIPT_NAME} /home/user/project --include-summary

    Exclude test files and logs:
        ${SCRIPT_NAME} /home/user/project --exclude '*test*,*.log'

    Save output to file with summary:
        ${SCRIPT_NAME} /home/user/project --output file --include-summary

    Complex pattern example:
        ${SCRIPT_NAME} /project --include 'src/*.js,lib/*.py' --exclude '*/test/*'

NOTES:
    - The script automatically excludes '${SUMMARY_FILENAME}' from processing
    - Hidden files and directories (starting with .) are excluded by default
    - Use --include-hidden to process all hidden files
    - Use --include with specific patterns to include only certain hidden files
    - Use --include-summary to add statistics at the end of the output
    - Patterns are matched against the relative path from the target folder
    - Use quotes around patterns to prevent shell expansion
    - File content is read using UTF-8 encoding

EOF
}

# Function to validate directory
validate_directory() {
    local dir="$1"
    
    if [[ -z "$dir" ]]; then
        error "Folder path is required"
        usage
        exit 1
    fi
    
    if [[ ! -d "$dir" ]]; then
        error "'$dir' is not a valid directory"
        exit 1
    fi
    
    if [[ ! -r "$dir" ]]; then
        error "Cannot read directory '$dir' (permission denied)"
        exit 1
    fi
}

# Function to parse pattern list
parse_patterns() {
    local pattern_string="$1"
    local -n pattern_array=$2  # nameref to the array
    
    # Clear the array first
    pattern_array=()
    
    # Parse comma-separated patterns
    while IFS=',' read -r pattern; do
        # Trim whitespace
        pattern="${pattern#"${pattern%%[![:space:]]*}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"
        
        if [[ -n "$pattern" ]]; then
            pattern_array+=("$pattern")
        fi
    done <<< "$pattern_string"
}

# Function to convert glob pattern to regex
glob_to_regex() {
    local pattern="$1"
    local regex=""
    
    # Escape special regex characters except glob wildcards
    regex=$(echo "$pattern" | sed 's/[.^$+{}()|[\]\\]/\\&/g')
    
    # Convert glob wildcards to regex
    regex="${regex//\*/.*}"
    regex="${regex//\?/.}"
    
    # Handle ** for recursive matching
    regex="${regex//\.\*\.\*/.*}"
    
    echo "^${regex}$"
}

# Function to check if file matches any pattern
matches_pattern() {
    local filepath="$1"
    shift
    local patterns=("$@")
    
    for pattern in "${patterns[@]}"; do
        # Try direct regex match first
        if [[ "$filepath" =~ $pattern ]]; then
            return 0
        fi
        
        # Try as glob pattern
        local regex
        regex=$(glob_to_regex "$pattern")
        if [[ "$filepath" =~ $regex ]]; then
            return 0
        fi
        
        # Try basename match for simple patterns
        local basename
        basename=$(basename "$filepath")
        if [[ "$basename" =~ $pattern ]] || [[ "$basename" =~ $regex ]]; then
            return 0
        fi
    done
    
    return 1
}

# Function to output content based on the selected mode
output_content() {
    local content="$1"
    
    if [[ "$output_mode" == "cli" ]]; then
        echo -e "$content"
    else
        echo -e "$content" >> "$output_file"
    fi
}

# Function to process a single file
process_file() {
    local file="$1"
    local relative_path="$2"
    
    # Check if file is readable
    if [[ ! -r "$file" ]]; then
        info "Skipping unreadable file: $relative_path"
        return
    fi
    
    # Check file size (warn for large files)
    local file_size=0
    if command -v stat >/dev/null 2>&1; then
        # Try to get file size (macOS first, then Linux)
        file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
    fi
    
    if (( file_size > 10485760 )); then  # 10MB
        info "Warning: Large file ($(( file_size / 1048576 ))MB): $relative_path"
    fi
    
    # Collect statistics if summary is requested
    if [[ "$include_summary" == true ]]; then
        # Get file extension
        local extension="${relative_path##*.}"
        if [[ "$extension" == "$relative_path" ]]; then
            extension="no_extension"
        else
            extension=".$extension"
        fi
        
        # Update statistics
        ((file_extensions["$extension"]++)) || file_extensions["$extension"]=1
        ((total_size += file_size))
        
        # Track largest file
        if (( file_size > largest_file_size )); then
            largest_file="$relative_path"
            largest_file_size=$file_size
        fi
    fi
    
    # Output file header
    output_content "# $relative_path"
    
    # Output file content
    local file_content
    if file_content=$(cat "$file" 2>/dev/null); then
        output_content "$file_content"
    else
        output_content "[Error reading file content]"
    fi
    
    # Add blank lines after content
    output_content ""
    output_content ""
    
    # Print progress message only for file output
    if [[ "$output_mode" == "file" ]]; then
        echo "Added: $relative_path"
    fi
}

# Function to generate and display summary
generate_summary() {
    local separator="================================================================================"
    
    output_content ""
    output_content "$separator"
    output_content "# SUMMARY STATISTICS"
    output_content "$separator"
    output_content ""
    
    # Files processed
    output_content "## Files Processed"
    output_content "- Total files analyzed: $processed_count"
    output_content "- Total files found: $file_count"
    if (( file_count > processed_count )); then
        output_content "- Files filtered out: $(( file_count - processed_count ))"
    fi
    output_content ""
    
    # Total size
    output_content "## Size Information"
    if (( total_size < 1024 )); then
        output_content "- Total size: ${total_size} bytes"
    elif (( total_size < 1048576 )); then
        output_content "- Total size: $(awk "BEGIN {printf \"%.2f\", $total_size/1024}") KB"
    elif (( total_size < 1073741824 )); then
        output_content "- Total size: $(awk "BEGIN {printf \"%.2f\", $total_size/1048576}") MB"
    else
        output_content "- Total size: $(awk "BEGIN {printf \"%.2f\", $total_size/1073741824}") GB"
    fi
    
    if [[ -n "$largest_file" ]]; then
        output_content "- Largest file: $largest_file ($(awk "BEGIN {printf \"%.2f\", $largest_file_size/1048576}") MB)"
    fi
    output_content ""
    
    # File types breakdown
    if [[ ${#file_extensions[@]} -gt 0 ]]; then
        output_content "## File Types Breakdown"
        # Sort extensions by count
        for ext in $(printf '%s\n' "${!file_extensions[@]}" | sort); do
            local count="${file_extensions[$ext]}"
            local percentage=$(awk "BEGIN {printf \"%.1f\", ($count/$processed_count)*100}")
            output_content "- $ext: $count files (${percentage}%)"
        done
        output_content ""
    fi
    
    # Applied filters
    output_content "## Applied Filters"
    if [[ "$use_include_filter" == true ]]; then
        output_content "- Include patterns: ${include_patterns[*]}"
    fi
    if [[ "$use_exclude_filter" == true ]]; then
        output_content "- Exclude patterns: ${exclude_patterns[*]}"
    fi
    if [[ "$exclude_hidden" == false ]]; then
        output_content "- Hidden files: included"
    else
        output_content "- Hidden files: excluded (default)"
    fi
    output_content ""
    
    # Timestamp
    output_content "## Generation Info"
    output_content "- Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
    output_content "- Source directory: $folder_path"
    if [[ "$output_mode" == "file" ]]; then
        output_content "- Output file: $output_file"
    fi
    output_content ""
    output_content "$separator"
}

# Parse command line arguments
parse_arguments() {
    local args=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                help_message
                exit 0
                ;;
            -H|--include-hidden)
                exclude_hidden=false
                shift
                ;;
            -s|--include-summary)
                include_summary=true
                shift
                ;;
            -v|--version)
                echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
                exit 0
                ;;
            -i|--include|--just-include)
                if [[ -z "${2:-}" ]]; then
                    error "'$1' requires a comma-separated list of patterns"
                    exit 1
                fi
                parse_patterns "$2" include_patterns
                use_include_filter=true
                shift 2
                ;;
            -e|--exclude)
                if [[ -z "${2:-}" ]]; then
                    error "'$1' requires a comma-separated list of patterns"
                    exit 1
                fi
                parse_patterns "$2" exclude_patterns
                use_exclude_filter=true
                shift 2
                ;;
            -o|--output)
                if [[ -z "${2:-}" ]]; then
                    error "'$1' requires a value (cli or file)"
                    exit 1
                fi
                if [[ "$2" != "cli" && "$2" != "file" ]]; then
                    error "'--output' value must be 'cli' or 'file'"
                    exit 1
                fi
                output_mode="$2"
                shift 2
                ;;
            -*)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    
    # Check if folder path was provided
    if [[ ${#args[@]} -eq 0 ]]; then
        error "Folder path is required"
        usage
        exit 1
    elif [[ ${#args[@]} -gt 1 ]]; then
        error "Multiple folder paths provided"
        usage
        exit 1
    fi
    
    folder_path="${args[0]}"
}

# Main execution function
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Validate directory
    validate_directory "$folder_path"
    
    # Resolve to absolute path
    folder_path=$(cd "$folder_path" && pwd)
    
    # Define output file path
    output_file="${folder_path}/${SUMMARY_FILENAME}"
    
    # Initialize output file if needed
    if [[ "$output_mode" == "file" ]]; then
        if [[ -e "$output_file" ]] && [[ ! -w "$output_file" ]]; then
            error "Cannot write to output file: $output_file"
            exit 1
        fi
        
        # Clear the output file
        > "$output_file"
        info "Output file: $output_file"
    fi
    
    # Build find command with proper exclusions
    local find_cmd=(find "$folder_path" -type f)
    
    # Always exclude the summary file
    find_cmd+=(\! -name "$SUMMARY_FILENAME")
    
    # Process files
    local file_count=0
    local processed_count=0
    local relative_path
    
    while IFS= read -r -d '' file; do
        ((file_count++)) || true  # Prevent exit on arithmetic operations
        
        # Calculate relative path
        relative_path="${file#"$folder_path/"}"
        
        # Check if we should exclude hidden files by default
        if [[ "$exclude_hidden" == true ]] && [[ "$relative_path" =~ (^|/)\. ]]; then
            # Skip hidden files unless explicitly included
            if [[ "$use_include_filter" == true ]] && [[ ${#include_patterns[@]} -gt 0 ]]; then
                if ! matches_pattern "$relative_path" "${include_patterns[@]}"; then
                    continue
                fi
                # If it matches an include pattern, process it despite being hidden
            else
                continue  # Skip hidden file
            fi
        fi
        
        # Apply exclude filter
        if [[ "$use_exclude_filter" == true ]] && [[ ${#exclude_patterns[@]} -gt 0 ]]; then
            if matches_pattern "$relative_path" "${exclude_patterns[@]}"; then
                continue
            fi
        fi
        
        # Apply include filter
        if [[ "$use_include_filter" == true ]] && [[ ${#include_patterns[@]} -gt 0 ]]; then
            if ! matches_pattern "$relative_path" "${include_patterns[@]}"; then
                continue
            fi
        fi
        
        # Process the file
        process_file "$file" "$relative_path"
        ((processed_count++)) || true  # Prevent exit on arithmetic operations
        
    done < <("${find_cmd[@]}" -print0 2>/dev/null)
    
    # Generate summary if requested
    if [[ "$include_summary" == true ]] && (( processed_count > 0 )); then
        generate_summary
    fi
    
    # Summary statistics
    if [[ "$output_mode" == "file" ]]; then
        success "Summary complete: $processed_count/$file_count files processed"
        success "Output saved to: $output_file"
    else
        if [[ "$include_summary" == false ]]; then
            info "Processed $processed_count/$file_count files"
        fi
    fi
}

# Trap to ensure clean exit
trap 'echo -e "\n${COLOR_ERROR}Script interrupted${COLOR_RESET}" >&2; exit 130' INT TERM

# Execute main function
main "$@"