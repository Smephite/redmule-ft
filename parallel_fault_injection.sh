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
echo "  Staring Seed               : $seed"

# Ask if the user wants to continue
# Only continue if user enters "y" or "Y" or presses Enter
read -p "Do you want to continue? ([y]/n) " -n 1 -r
if [[ -z $REPLY || $REPLY =~ ^[Yy]$ ]]; then
    echo ""
else
    echo "Exiting..."
    echo "Entered response: $REPLY"
    exit 1
fi

timestamp=$(date +"%Y%m%d_%H%M")  # Get timestamp in YYYYMMDD_HHMMSS format
echo "Logging to transcript file: transcript_${timestamp}_*.log"

trap 'kill 0; exit' SIGINT SIGTERM EXIT

log_file="transcript_${timestamp}_compile.log"

echo "Compile RTL..."
make hw-all > "$log_file" 2>&1

echo "Generate the test vectors..."
make golden >> "$log_file" 2>&1

echo "Building the software..."
riscv make all SOFTWARE_ENABLE_REDUNDANCY="$SOFTWARE_ENABLE_REDUNDANCY" >> "$log_file" 2>&1

echo "Starting $num_threads parallel test instances..."
for ((i=0; i<num_threads; i++)); do
    log_file="transcript_${timestamp}_${i}.log"

    echo "Starting instance $i with seed $seed (logging to $log_file)..."

    # Run the fault injection command in the background
    make analysis \
        HARDWARE_FULL_REDUNDANCY="$HARDWARE_FULL_REDUNDANCY" \
        HARDWARE_ECC="$HARDWARE_ECC" \
        tests="$tests" \
        seed="$seed" \
        thread_id="$i" \
        num_threads="$num_threads" > "$log_file" 2>&1 &
done

# Wait for all background processes
wait

echo "All instances have completed."


