#!/bin/bash

# Usage: ./parallel_fault_injection.sh <SOFTWARE_ENABLE_REDUNDANCY> <HARDWARE_FULL_REDUNDANCY> <HARDWARE_ECC> <tests> <num_threads>
# Example: ./parallel_fault_injection.sh 1 1 1 10000 4

SOFTWARE_ENABLE_REDUNDANCY=${1:-1}
HARDWARE_FULL_REDUNDANCY=${2:-1}
HARDWARE_ECC=${3:-1}
tests=${4:-10000}
num_threads=${5:-4}
seed=0  # Initial seed value
timestamp=$(date +"%Y%m%d_%H%M")  # Get timestamp in YYYYMMDD_HHMMSS format

log_file="transcript_${timestamp}.log"

trap 'echo "Stopping all instances..."; kill 0; exit' SIGINT SIGTERM EXIT

echo "Compile RTL..."
riscv make hw-all BUILD_DIR=work > "$log_file" 2>&1

echo "Building the software..."
riscv make golden all SOFTWARE_ENABLE_REDUNDANCY="$SOFTWARE_ENABLE_REDUNDANCY" >> "$log_file" 2>&1

echo "Starting $num_threads parallel test instances..."
for ((i=0; i<num_threads; i++)); do
    log_file="transcript_${timestamp}_${i}.log"

    echo "Starting instance $i with seed $seed (logging to $log_file)..."

    # Run the command in the background and redirect output
    riscv make analysis HARDWARE_FULL_REDUNDANCY="$HARDWARE_FULL_REDUNDANCY" HARDWARE_ECC="$HARDWARE_ECC" tests="$tests" seed="$seed" thread_id="$i" num_threads="$num_threads" > "$log_file" 2>&1 &
done

# Wait for all background processes
wait

echo "All instances have completed."


