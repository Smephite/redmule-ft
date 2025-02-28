#!/bin/bash

# Usage:
# ./parallel_fault_injection.sh [SOFTWARE_ENABLE_REDUNDANCY] [HARDWARE_FULL_REDUNDANCY] [HARDWARE_ECC] [tests] [num_threads] [seed]
#
# Example:
# ./parallel_fault_injection.sh 1 1 1 10000 4 0
#
# All parameters are optional, and defaults are provided.

SOFTWARE_ENABLE_REDUNDANCY=${1:-1}
HARDWARE_FULL_REDUNDANCY=${2:-1}
HARDWARE_ECC=${3:-1}
tests=${4:-1}
num_threads=${5:-1}
seed=${6:-0}

# Print help message if no arguments are provided
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 [SOFTWARE_ENABLE_REDUNDANCY] [HARDWARE_FULL_REDUNDANCY] [HARDWARE_ECC] [tests] [num_threads] [seed]"
    echo ""
    echo "Arguments:"
    echo "  SOFTWARE_ENABLE_REDUNDANCY: 0 or 1 (default: 1)"
    echo "  HARDWARE_FULL_REDUNDANCY: 0 or 1 (default: 1)"
    echo "  HARDWARE_ECC: 0 or 1 (default: 1)"
    echo "  tests: Number of injections (default: 10000)"
    echo "  num_threads: Number of parallel threads (default: 1)"
    echo "  seed: Starting seed (default: 0)"
    echo ""
    echo "Example: (SOFTWARE_ENABLE_REDUNDANCY, HARDWARE_FULL_REDUNDANCY, HARDWARE_ECC)"
    echo " - Baseline: $0 0 0 0"
    echo " - Data Protection: $0 1 0 1"
    echo " - Full Redundancy: $0 1 1 1"
    exit 1
fi

# Print the configuration
echo "Configuration:"
echo "  Hardware Redundancy Feature: $HARDWARE_FULL_REDUNDANCY"
echo "  Hardware ECC Feature       : $HARDWARE_ECC"
echo "  Software Enable Redundancy : $SOFTWARE_ENABLE_REDUNDANCY"
echo "  Number of Injections       : $tests"
echo "  Number of Threads          : $num_threads"
echo "  Starting Seed              : $seed"

# Ask if the user wants to continue
read -p "Do you want to continue? ([y]/n) " -n 1 -r
if [[ -z $REPLY || $REPLY =~ ^[Yy]$ ]]; then
    echo ""
else
    echo "Exiting..."
    echo "Entered response: $REPLY"
    exit 1
fi

timestamp=$(date +"%Y%m%d_%H%M")  # Get timestamp in YYYYMMDD_HHMM format
echo "Prepare Simulation (logging to transcript_${timestamp}_compile*.log)..."

trap 'kill 0; exit' SIGINT SIGTERM EXIT

log_file="transcript_${timestamp}_compile.log"

echo " - Compile RTL..."
make hw-all > "$log_file" 2>&1

echo " - Generate the test vectors..."
make golden >> "$log_file" 2>&1

echo " - Building the software..."
riscv make all SOFTWARE_ENABLE_REDUNDANCY="$SOFTWARE_ENABLE_REDUNDANCY" >> "$log_file" 2>&1

echo "Starting $num_threads parallel fault injection runner..."
pids=()

timestamp_short=$(date +"%Y%m%d_%H%M")  # Get timestamp in YYYYMMDD_HHMM format
timestamp_short=${timestamp_short%?}

for ((i=0; i<num_threads; i++)); do
    log_file="transcript_${timestamp}_${i}.log"

    echo " - Starting instance $i with seed $seed (logging to $log_file)..."

    # Run the fault injection command in the background
    make analysis \
        HARDWARE_FULL_REDUNDANCY="$HARDWARE_FULL_REDUNDANCY" \
        HARDWARE_ECC="$HARDWARE_ECC" \
        tests="$tests" \
        seed="$seed" \
        thread_id="$i" \
        num_threads="$num_threads" > "$log_file" 2>&1 &

    pids+=($!)
done


# Monitor progress
progress=0

while true; do

    # Find the latest CSV file based on timestamp range (to account for small timing differences)
    csv_files=(vulnerability_${timestamp_short}*.csv)
    latest_csv=""

    # Check if CSV files exist and select the most recent one
    if [ ${#csv_files[@]} -gt 0 ]; then
        latest_csv=$(ls -t vulnerability_${timestamp_short}*.csv 2>/dev/null | head -n 1)
    fi

    if [[ -z "$latest_csv" ]]; then
        printf "\rProgress: [--------------------------------------------------] 0%% (Log files not found yet...)"
        continue
    fi

    # Generate a wildcard pattern to match related CSV files based on the latest csv file
    csv_basename=$(echo "$latest_csv" | sed -E 's/_[0-9]+\.csv/*\.csv/')

    # Check if all threads are still running
    for pid in "${pids[@]}"; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo -e "\nWARNING: Process $pid has stopped!"
            pids=(${pids[@]/$pid})
        fi
    done

    # Count total lines in all matching CSV files
    total_lines=$(cat $csv_basename 2>/dev/null | wc -l)

    # Calculate progress
    progress=$((total_lines - num_threads))
    progress=$((progress < 0 ? 0 : progress))
    progress_percent=$((progress * 100 / tests))
    progress_percent=$((progress_percent > 100 ? 100 : progress_percent))

    # Display progress bar
    bar_length=50
    filled_length=$((bar_length * progress_percent / 100))
    bar=$(printf "%-${filled_length}s" "#" | tr ' ' '#')
    empty=$(printf "%-$((bar_length - filled_length))s" "-")

    printf "\rProgress: [%s%s] %d%% (%d/%d tests)                               " "$bar" "$empty" "$progress_percent" "$progress" "$tests"

    # Break all pids have stopped
    if [ ${#pids[@]} -eq 0 ]; then
        break
    fi

    sleep 1  # Adjust frequency of updates
done

echo -e "\nAll instances have completed."

# Merge all CSV files
echo "Merging CSV files..."

# Find latest csv file matching the basename and remove the thread number
latest_csv=$(ls -t vulnerability_${timestamp_short}*.csv 2>/dev/null | head -n 1)
file_pattern=$(echo "$latest_csv" | sed -E 's/_[0-9]+\.csv/*\.csv/')

echo " - Merging CSV files matching the pattern: $file_pattern"

# Find all matching CSV files
csv_files=($(ls $file_pattern 2>/dev/null))

# Check if any CSV files exist
if [ ${#csv_files[@]} -eq 0 ]; then
    echo "No CSV files found matching the pattern '$file_pattern'!"
    exit 1
fi

# Extract the common filename prefix (remove wildcards and trailing parts)
common_part=$(echo "$file_pattern" | sed -E 's/[*?].*//')

# Define the output file using the common filename part and timestamp
output_file="${common_part}.csv"

echo " - Merging ${#csv_files[@]} CSV files into $output_file..."

# Extract header from the first CSV file
head -n 1 "${csv_files[0]}" > "$output_file"

# Concatenate all CSV files excluding the header, then sort by first column (seed)
tail -n +2 -q "${csv_files[@]}" | sort -t, -k1,1n >> "$output_file"

echo "Merge complete: $output_file"

# Exit without triggering the trap
trap - SIGINT SIGTERM EXIT

