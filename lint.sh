#!/bin/bash

#----------------------------------------------------
# This is an automated script for Verilog linting.
# It uses Verilator to check code for style issues and potential problems.
#----------------------------------------------------

# Set the list of your Verilog files
VERILOG_FILES="alu.v testbench.v"

# Set Verilator's linting options
# --lint-only: Performs linting only, without generating a simulator.
# -Wall: Enables all common warnings.
LINT_OPTIONS="--lint-only -Wall"

echo "=========================================="
echo "    Starting Verilog Lint Check"
echo "=========================================="
echo "Checking files: $VERILOG_FILES"
echo "Using Verilator options: $LINT_OPTIONS"
echo "------------------------------------------"

# Execute the Verilator lint check
verilator $LINT_OPTIONS $VERILOG_FILES

# Check Verilator's exit code to determine success
if [ $? -eq 0 ]; then
    echo "------------------------------------------"
    echo "✅ Lint check passed successfully!"
    echo "   No serious warnings or errors found."
    echo "=========================================="
    exit 0
else
    echo "------------------------------------------"
    echo "❌ Lint check failed!"
    echo "   Please review the warnings and errors above."
    echo "=========================================="
    exit 1
fi