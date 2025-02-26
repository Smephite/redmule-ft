#!/bin/bash

# Usage: ./run_parallel_tests.sh <USE_REDUNDANCY> <USE_ECC> <tests> <num_threads>
# Example: ./run_parallel_tests.sh 1 1 10000 4

USE_REDUNDANCY=${1:-1}
USE_ECC=${2:-1}
tests=${3:-10000}
num_threads=${4:-4}
seed=0  # Initial seed value
timestamp=$(date +"%Y%m%d_%H%M")  # Get timestamp in YYYYMMDD_HHMMSS format

log_file="transcript_${timestamp}.log"

trap 'echo "Stopping all instances..."; kill 0; exit' SIGINT SIGTERM EXIT

echo "Compile RTL..."
riscv make hw-all USE_REDUNDANCY="$USE_REDUNDANCY" USE_ECC="$USE_ECC" BUILD_DIR=work > "$log_file" 2>&1

echo "Building the software..."
riscv make golden USE_REDUNDANCY="$USE_REDUNDANCY" USE_ECC="$USE_ECC" all >> "$log_file" 2>&1

echo "Starting $num_threads parallel test instances..."
for ((i=0; i<num_threads; i++)); do
    log_file="transcript_${timestamp}_${i}.log"

    echo "Starting instance $i with seed $seed (logging to $log_file)..."

    # Run the command in the background and redirect output
    riscv make analysis USE_REDUNDANCY="$USE_REDUNDANCY" USE_ECC="$USE_ECC" tests="$tests" seed="$seed" thread_id="$i" num_threads="$num_threads" > "$log_file" 2>&1 &
done

# Wait for all background processes
wait

echo "All instances have completed."


