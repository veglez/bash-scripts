#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 <folder_path> [--just-include pattern1,pattern2,...] [--exclude pattern1,pattern2,...] [--output cli|file]"
    exit 1
}

# Function to display detailed help information
help_message() {
    echo "$(basename "$0") - Generate a summary of files in a specified folder."
    echo ""
    echo "Usage:"
    echo "  $(basename "$0") <folder_path> [--just-include pattern1,pattern2,...] [--exclude pattern1,pattern2,...] [--output cli|file]"
    echo ""
    echo "Description:"
    echo "  This script generates a summary of files in the specified folder. By default, it includes"
    echo "  all files in the folder (excluding 'folder_summary.txt' if it exists) and outputs the"
    echo "  summary to the command line. You can optionally limit the summary to files matching"
    echo "  specific patterns (including regex) and choose to output to a file instead."
    echo ""
    echo "Options:"
    echo "  <folder_path>              The path to the folder to summarize. Required."
    echo "  --just-include pattern1,pattern2,..."
    echo "                             Optional. A comma-separated list of patterns (e.g., *.py, note.*)"
    echo "                             to include in the summary. If specified, only matching files are processed."
    echo "  --exclude pattern1,pattern2,..."
    echo "                             Optional. A comma-separated list of patterns to exclude from the summary."
    echo "                             Files or folders matching these patterns will be skipped."
    echo "  --output cli|file          Optional. Specifies the output destination:"
    echo "                             'cli' for command line (default), 'file' for 'folder_summary.txt'."
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") /home/user/docs"
    echo "    Summarize all files in /home/user/docs, output to terminal."
    echo "  $(basename "$0") /home/user/docs --just-include '*.py,note.txt' --output file"
    echo "    Summarize only Python files and note.txt, output to folder_summary.txt."
    echo "  $(basename "$0") /home/user/docs --exclude 'node_modules,*.log' --output file"
    echo "    Summarize all files except those in node_modules folders and .log files."
}

# Initialize variables
FOLDER_PATH=""
JUST_INCLUDE=0
EXCLUDE=0
OUTPUT_MODE="cli"
INCLUDE_PATTERNS=()
EXCLUDE_PATTERNS=()

# Parse all arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            help_message
            exit 0
            ;;
        --just-include)
            if [ -z "$2" ]; then
                echo "Error: '--just-include' flag requires a comma-separated list of patterns."
                exit 1
            fi
            JUST_INCLUDE=1
            IFS=',' read -r -a INCLUDE_PATTERNS <<< "$2"
            shift 2
            ;;
        --exclude)
            if [ -z "$2" ]; then
                echo "Error: '--exclude' flag requires a comma-separated list of patterns."
                exit 1
            fi
            EXCLUDE=1
            IFS=',' read -r -a EXCLUDE_PATTERNS <<< "$2"
            shift 2
            ;;
        --output)
            if [ -z "$2" ]; then
                echo "Error: '--output' flag requires a value (cli or file)."
                exit 1
            fi
            if [[ "$2" != "cli" && "$2" != "file" ]]; then
                echo "Error: '--output' value must be 'cli' or 'file'."
                exit 1
            fi
            OUTPUT_MODE="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option '$1'"
            usage
            ;;
        *)
            if [ -z "$FOLDER_PATH" ]; then
                FOLDER_PATH="$1"
            else
                echo "Error: Multiple folder paths provided."
                usage
            fi
            shift
            ;;
    esac
done

# Check if folder path is provided and valid
if [ -z "$FOLDER_PATH" ]; then
    echo "Error: Folder path is required."
    usage
fi

if [ ! -d "$FOLDER_PATH" ]; then
    echo "Error: '$FOLDER_PATH' is not a valid directory."
    exit 1
fi

# Define output file path
OUTPUT_FILE="$FOLDER_PATH/folder_summary.txt"

# Create or empty the output file if output mode is 'file'
if [ "$OUTPUT_MODE" = "file" ]; then
    > "$OUTPUT_FILE"
fi

# Function to output content based on the selected mode
output_content() {
    local content="$1"
    if [ "$OUTPUT_MODE" = "cli" ]; then
        echo -e "$content"
    else
        echo -e "$content" >> "$OUTPUT_FILE"
    fi
}

# Iterate over files in the folder (excluding the summary file)
find "$FOLDER_PATH" -type f \! -name "folder_summary.txt" | while read -r FILE; do
    # Get the relative path for checking against patterns
    RELATIVE_PATH="${FILE#$FOLDER_PATH/}"
    
    # If the --exclude flag is active, check if this file matches any exclusion pattern
    if [ "$EXCLUDE" -eq 1 ]; then
        skip_file=0
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            # Check if the pattern matches the file path
            if [[ "$RELATIVE_PATH" =~ $pattern || "$RELATIVE_PATH" =~ ^${pattern//\*/.*}$ ]]; then
                skip_file=1
                break
            fi
        done
        # If the file matches an exclusion pattern, skip it
        if [ $skip_file -eq 1 ]; then
            continue
        fi
    fi
    
    # If the --just-include flag is active, check if this file's base name matches any pattern
    if [ "$JUST_INCLUDE" -eq 1 ]; then
        basefile=$(basename "$FILE")
        match_found=0
        for pattern in "${INCLUDE_PATTERNS[@]}"; do
            # Convert glob-like patterns (e.g., *.py) to work with [[ ]] test
            if [[ "$RELATIVE_PATH" =~ ^${pattern//\*/.*}$ ]]; then
                match_found=1
                break
            fi
        done
        # If the file doesn't match any pattern, skip it
        if [ $match_found -eq 0 ]; then
            continue
        fi
    fi

    # Compute the relative path and prepare the header and content
    content="# $RELATIVE_PATH\n$(cat "$FILE")\n\n"
    output_content "$content"

    # Print the addition message only if the output mode is 'file'
    if [ "$OUTPUT_MODE" = "file" ]; then
        echo "Added $RELATIVE_PATH to ${OUTPUT_MODE}"
    fi
done

if [ "$OUTPUT_MODE" = "file" ]; then
    echo "Summary file created at: $OUTPUT_FILE"
fi