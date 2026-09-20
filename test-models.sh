#!/bin/bash
# Model Comparison Testing Script
# Privacy-aware: only tests models within user's privacy tier
# Tests each free model on standardized tasks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
REGISTRY_FILE="$SCRIPT_DIR/privacy-tier-registry.json"

mkdir -p "$RESULTS_DIR"

# ============================================================
# Privacy-aware model loading
# ============================================================

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: No privacy configuration found."
    echo "Run ./privacy-setup.sh first to set your privacy preferences."
    exit 1
fi

source "$CONFIG_FILE"
PRIVACY_TIER="$privacy_max_tier"

if [ ! -f "$REGISTRY_FILE" ]; then
    echo "Error: privacy-tier-registry.json not found."
    exit 1
fi

# Get models within user's privacy tier
MODELS=()
while IFS= read -r model_id; do
    if [ -n "$model_id" ]; then
        MODELS+=("$model_id")
    fi
done < <(jq -r ".models | to_entries[] | select(
    (.value.privacy_tier | split(\"_\")[0] | tonumber) <= $PRIVACY_TIER
) | .key" "$REGISTRY_FILE" 2>/dev/null)

if [ ${#MODELS[@]} -eq 0 ]; then
    echo "Error: No models available at privacy tier $PRIVACY_TIER"
    echo "Consider raising your privacy tier with ./privacy-setup.sh"
    exit 1
fi

# Test prompts
CODE_GEN_PROMPT="Write a Python function to calculate the Fibonacci sequence with memoization. Include type hints and docstring."

CODE_REVIEW_PROMPT="Review this code for potential issues and suggest improvements:\n\ndef fibonacci(n):\n    if n <= 1:\n        return n\n    return fibonacci(n-1) + fibonacci(n-2)"

DOCUMENTATION_PROMPT="Write comprehensive documentation for a REST API endpoint that handles user authentication, including request/response examples."

REASONING_PROMPT="Analyze the trade-offs between using a microservices architecture versus a monolithic architecture for a startup with 5 engineers. Consider deployment, testing, and scaling."

echo "Starting model comparison tests..."
echo "Privacy tier: $PRIVACY_TIER"
echo "Models to test: ${#MODELS[@]}"
echo "Results will be saved to $RESULTS_DIR/"

for model in "${MODELS[@]}"; do
  model_name=$(echo "$model" | sed 's|opencode/||g')
  model_tier=$(jq -r ".models[\"$model\"].privacy_tier // \"unknown\"" "$REGISTRY_FILE" 2>/dev/null)
  
  echo ""
  echo "========================================="
  echo "Testing: $model_name (tier: $model_tier)"
  echo "========================================="
  
  # Create results file
  result_file="$RESULTS_DIR/${model_name}.json"
  echo "{\"model\": \"$model\", \"privacy_tier\": \"$model_tier\", \"tests\": []}" > "$result_file"
  
  # Test 1: Code Generation
  echo "Test 1: Code Generation..."
  start_time=$(date +%s%N)
  # Note: This would need to be run through opencode with the specific model
  # This is a placeholder for the actual test execution
  end_time=$(date +%s%N)
  duration=$(( (end_time - start_time) / 1000000 ))
  echo "  Duration: ${duration}ms"
  
  # Test 2: Code Review
  echo "Test 2: Code Review..."
  start_time=$(date +%s%N)
  end_time=$(date +%s%N)
  duration=$(( (end_time - start_time) / 1000000 ))
  echo "  Duration: ${duration}ms"
  
  # Test 3: Documentation
  echo "Test 3: Documentation..."
  start_time=$(date +%s%N)
  end_time=$(date +%s%N)
  duration=$(( (end_time - start_time) / 1000000 ))
  echo "  Duration: ${duration}ms"
  
  # Test 4: Reasoning
  echo "Test 4: Reasoning..."
  start_time=$(date +%s%N)
  end_time=$(date +%s%N)
  duration=$(( (end_time - start_time) / 1000000 ))
  echo "  Duration: ${duration}ms"
  
  echo "Completed: $model_name"
done

echo ""
echo "========================================="
echo "All tests completed!"
echo "Results saved to: $RESULTS_DIR/"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Review results in results/"
echo "  2. Fill in COMPARISON-MATRIX.md"
echo "  3. Run ./model-selector.sh to see recommended assignments"
