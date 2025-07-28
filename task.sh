#!/bin/bash

# Quick tasks script for abhinivesha
# Usage: ./task.sh {a|b|c|d}

case "$1" in
    "a")
        echo "Task: hot reload build or hot reload"
        ./build_hot_reload.sh
        ;;
    "b")
        echo "Task: run"
        ./game_hot_reload.bin
        ;;
    "c")
        echo "Task: Build and Run"
        ./build_hot_reload.sh
        ./game_hot_reload.bin
        ;;
    "d")
        echo "Executing task D..."
        # Add your task here
        ;;
    *)
        echo "Usage: $0 {a|b|c|d}"
        echo "  a - Task A"
        echo "  b - Task B"
        echo "  c - Task C"
        echo "  d - Task D"
        exit 1
        ;;
esac
