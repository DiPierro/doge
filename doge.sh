#!/bin/bash

# See documentation for this API: https://api.doge.gov/docs

# Check if endpoint argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <endpoint>"
    echo "Example: $0 contracts"
    echo "Example: $0 grants"
    echo "Example: $0 leases"
    echo "Example: $0 payments"
    exit 1
fi

ENDPOINT="$1"
 
# Define the base URL and output files dynamically
if [[ "$ENDPOINT" == "payments" ]]; then
    BASE_URL="https://api.doge.gov/${ENDPOINT}?per_page=500&page="
else
    BASE_URL="https://api.doge.gov/savings/${ENDPOINT}?sort_by=savings&sort_order=desc&per_page=500&page="
fi

OUTPUT_JSON="${ENDPOINT}.json"
LOG_FILE="${ENDPOINT}_scraper.log"

# Initialize log file
echo "$(date): Starting ${ENDPOINT} scraper" > "$LOG_FILE"

# Array to store data
all_data=()
total_downloaded=0
failed_pages=()

# Function to log messages
log_message() {
    echo "$(date): $1" | tee -a "$LOG_FILE"
}

# Function to extract value from JSON using basic tools
extract_json_value() {
    local json="$1"
    local key="$2"
    echo "$json" | grep -o "\"$key\":[0-9]*" | cut -d':' -f2
}

# Function to extract data array from JSON
extract_data() {
    local json_data="$1"
    local key="$2" # Pass the endpoint key as the second argument

    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed or not in PATH." >&2
        return 1
    fi

    # Note: jq will output an error if json_data is not valid JSON.
    # Example: jq: error: Invalid numeric literal at line 1, column 19 (while parsing '{"key":nu`ll}')
    echo "$json_data" | jq --arg endpoint_key "$key" '.result.[$endpoint_key]'

    # To check jq's exit status (0 for success)
    # local status=$?
    # if [ $status -ne 0 ]; then
    #     echo "jq command failed with status $status" >&2
    # fi
    # return $status
}

# Function to check if API response was successful
check_success() {
    local json="$1"
    echo "$json" | grep -q '"success":true'
}

log_message "Fetching first page to determine total pages for ${ENDPOINT} endpoint..."

# Fetch the first page to get metadata only
FIRST_PAGE_JSON="first_page.json"
curl -sS "${BASE_URL}1" \
  --compressed \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:137.0) Gecko/20100101 Firefox/137.0' \
  -H 'Accept: */*' \
  -H 'Accept-Language: en-US,en;q=0.5' \
  -H 'Accept-Encoding: gzip, deflate, br, zstd' \
  -H 'Referer: https://www.doge.gov/' \
  -H 'Origin: https://www.doge.gov' \
  -H 'Connection: keep-alive' \
  -H 'Sec-Fetch-Dest: empty' \
  -H 'Sec-Fetch-Mode: cors' \
  -H 'Sec-Fetch-Site: same-site' \
  -H 'Priority: u=4' \
  -H 'TE: trailers' > "$FIRST_PAGE_JSON"

# Check if first page was downloaded successfully
if [ ! -s "$FIRST_PAGE_JSON" ]; then
    log_message "ERROR: Failed to download first page. Exiting."
    exit 1
fi

# Extract metadata from first page
first_page_data=$(cat "$FIRST_PAGE_JSON")
TOTAL_PAGES=$(extract_json_value "$first_page_data" "pages")
EXPECTED_TOTAL=$(extract_json_value "$first_page_data" "total_results")

if [ -z "$TOTAL_PAGES" ] || [ -z "$EXPECTED_TOTAL" ]; then
    log_message "ERROR: Could not extract metadata from first page. Exiting."
    exit 1
fi

log_message "Found $TOTAL_PAGES total pages with $EXPECTED_TOTAL expected results"

# Clean up first page temp file (we'll re-fetch it in the main loop)
rm "$FIRST_PAGE_JSON"

# Loop through all pages including page 1
for ((page=1; page<=TOTAL_PAGES; page++)); do
    log_message "Fetching data for page $page..."
    TEMP_JSON="page_${page}.json"
    
    # Download the JSON data for the current page
    curl -sS "${BASE_URL}${page}" \
      --compressed \
      -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:137.0) Gecko/20100101 Firefox/137.0' \
      -H 'Accept: */*' \
      -H 'Accept-Language: en-US,en;q=0.5' \
      -H 'Accept-Encoding: gzip, deflate, br, zstd' \
      -H 'Referer: https://www.doge.gov/' \
      -H 'Origin: https://www.doge.gov' \
      -H 'Connection: keep-alive' \
      -H 'Sec-Fetch-Dest: empty' \
      -H 'Sec-Fetch-Mode: cors' \
      -H 'Sec-Fetch-Site: same-site' \
      -H 'Priority: u=4' \
      -H 'TE: trailers' > "$TEMP_JSON"

    # Add small delay between requests to be respectful
    sleep 0.2

    if [ -s "$TEMP_JSON" ]; then
        # Check if the API response was successful
        page_data=$(cat "$TEMP_JSON")
        
        if check_success "$page_data"; then
            # Extract data from this page
            page_data_items=$(extract_data "$page_data" "$ENDPOINT")
            if [ -n "$page_data_items" ]; then
                # Count items in this page
                page_count=$(echo "$page_data_items" | grep -o '{' | wc -l)
                total_downloaded=$((total_downloaded + page_count))
                all_data+=("$page_data_items")
                log_message "Page $page: Downloaded $page_count items"
            else
                log_message "WARNING: No data found in page $page"
                failed_pages+=($page)
            fi
        else
            log_message "WARNING: API returned success=false for page $page (${BASE_URL}${page})"
            failed_pages+=($page)
        fi
        
        rm "$TEMP_JSON" # Clean up temporary file
    else
        log_message "ERROR: Failed to download page $page (${BASE_URL}${page})"
        failed_pages+=($page)
    fi
done

# Create the final JSON file with all data
log_message "Creating consolidated JSON file: $OUTPUT_JSON"
echo "[" > "$OUTPUT_JSON"

# Combine all data chunks with proper comma separation
all_data_combined=""
for data_chunk in "${all_data[@]}"; do
    if [ -n "$data_chunk" ]; then
        if [ -z "$all_data_combined" ]; then
            all_data_combined="$data_chunk"
        else
            all_data_combined="$all_data_combined,$data_chunk"
        fi
    fi
done

# Write the combined data to the file
if [ -n "$all_data_combined" ]; then
    echo "$all_data_combined" >> "$OUTPUT_JSON"
fi

echo "]" >> "$OUTPUT_JSON"

# Final validation and logging
log_message "Download completed. Downloaded $total_downloaded items (expected: $EXPECTED_TOTAL)"

# Check if total matches expected
if [ "$total_downloaded" -ne "$EXPECTED_TOTAL" ]; then
    log_message "WARNING: Downloaded item count ($total_downloaded) does not match expected total ($EXPECTED_TOTAL)"
fi

# Log failed pages if any
if [ ${#failed_pages[@]} -gt 0 ]; then
    log_message "WARNING: Failed to download ${#failed_pages[@]} pages: ${failed_pages[*]}"
    for failed_page in "${failed_pages[@]}"; do
        log_message "Failed URL: ${BASE_URL}${failed_page}"
    done
fi

log_message "Script completed. Results saved to $OUTPUT_JSON, logs saved to $LOG_FILE"