#!/bin/bash

# Start the SSH service
sudo systemctl start sshd

# Function to stop SSH service on exit
cleanup() {
    echo "
Stopping SSH service..."
    sudo systemctl stop sshd
    exit
}

# Trap the Ctrl+C signal (SIGINT)
trap cleanup SIGINT

echo "SSH service have started for a minute. or Press Ctrl+C to stop."

# Set the counter
COUNTER=0

# Loop until COUNTER is greater than or equal to 1
while [ $COUNTER -lt 1 ]; do
    sleep 120
    COUNTER=3
done

# Stop the SSH service
sudo systemctl stop sshd
