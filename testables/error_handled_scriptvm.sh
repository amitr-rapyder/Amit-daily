#!/bin/bash
set -euo pipefail

# Configuration through environment variables or parameters
RESOURCE_GROUP="${RESOURCE_GROUP:-CoE}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-amitdemovm}"
CONTAINER_NAME="${CONTAINER_NAME:-amitdemovm}"
OUTPUT_DIR="/home/amitdemo"
OUTPUT_FILE="$(mktemp -p "$OUTPUT_DIR")"

cleanup() {
    # Clean up temporary files
    rm -f "$OUTPUT_FILE"
    # Clear sensitive variables
    unset STORAGE_KEY
}

trap cleanup EXIT

log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >&2
}

create_and_upload_file() {
    log_message "INFO" "Creating new file..."
    
    # Use managed identity without exposing credentials
    if ! az login --identity >/dev/null 2>&1; then
        log_message "ERROR" "Failed to login with managed identity"
        return 1
    }

    # Generate content
    current_date=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "Date and Time:\n$current_date" > "$OUTPUT_FILE"

    # Validate file size before upload
    local file_size
    file_size=$(stat -f %z "$OUTPUT_FILE" 2>/dev/null || stat -c %s "$OUTPUT_FILE")
    if [ "$file_size" -gt 100000000 ]; then  # 100MB limit example
        log_message "ERROR" "File size exceeds limit"
        return 1
    }

    blob_path="$(date '+%Y/%m/%d')/output.txt"

    # Use SAS token or managed identity instead of storage key
    if ! az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login \
        --container-name "$CONTAINER_NAME" \
        --file "$OUTPUT_FILE" \
        --name "$blob_path" \
        --overwrite true >/dev/null; then
        log_message "ERROR" "Failed to upload blob"
        return 1
    }

    log_message "INFO" "File uploaded successfully"
    return 0
}

test_date_access() {
    log_message "INFO" "Starting blob access check..."

    local max_retries=5
    local retry_count=0
    local check_date
    check_date=$(date -d "9 days ago" '+%Y/%m/%d')
    local target_blob_path="$check_date/output.txt"

    while [ $retry_count -lt $max_retries ]; do
        ((retry_count++))
        log_message "INFO" "Attempt $retry_count of $max_retries"

        if az storage blob exists \
            --account-name "$STORAGE_ACCOUNT" \
            --auth-mode login \
            --container-name "$CONTAINER_NAME" \
            --name "$target_blob_path" \
            --query "exists" \
            -o tsv 2>/dev/null | grep -q "true"; then
            log_message "INFO" "Blob found successfully"
            return 0
        fi

        log_message "INFO" "Blob not found - creating new file..."
        if ! create_and_upload_file; then
            return 1
        fi

        if [ $retry_count -eq $max_retries ]; then
            log_message "ERROR" "Maximum retry attempts reached"
            return 1
        fi

        sleep 5
    done

    return 1
}

main() {
    log_message "INFO" "=== Script Started ==="
    if ! test_date_access; then
        log_message "ERROR" "=== Script Failed ==="
        exit 1
    fi
    log_message "INFO" "=== Script Completed Successfully ==="
    exit 0
}

main
