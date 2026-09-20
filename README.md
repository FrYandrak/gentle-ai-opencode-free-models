# OpenCode Free Models Comparison

A comprehensive comparison of free models available through OpenCode Zen for use with Gentle-AI workflows.

## Overview

OpenCode offers several free models (available for a limited time) that can be used without API keys. This document compares their capabilities and recommends optimal usage in Gentle-AI SDD (Spec-Driven Development) workflows.

## Available Free Models

| Model | ID | Context | Output | Endpoint |
|-------|-----|---------|--------|----------|
| MiMo-V2.5 Free | `opencode/mimo-v2.5-free` | 262,144 | 6,536 | chat/completions |
| Ling 3.0 Flash Fin Free | `opencode/ling-3.0-flash-fin-free` | 262,144 | 131,072 | chat/completions |
| Nemotron 3 Ultra Free | `opencode/nemotron-3-ultra-free` | 1,000,000 | 131,072 | chat/completions |
| Nemotron 3.5 Lightning Free | `opencode/nemotron-3.5-lightning-free` | 262,144 | 131,072 | chat/completions |
| Muse Spark 1.3 Contributor Free | `opencode/muse-spark-1.3-contributor-free` | 262,144 | 131,072 | responses |
| Big Pickle | `opencode/big-pickle` | 262,144 | 131,072 | chat/completions |
| DeepSeek V4 Flash Free | `opencode/deepseek-v4-flash-free` | 262,144 | 131,072 | chat/completions |
| JEV 1.13 Free | `opencode/jev-1.13-free` | 262,144 | 131,072 | chat/completions |

## Model Analysis & Recommendations

### 1. MiMo-V2.5 Free (`mimo-v2.5-free`)
**Provider:** Xiaomi | **Architecture:** 32B parameters

**Strengths:**
- Excellent reasoning capabilities
- Strong performance on code generation
- Good instruction following
- Balanced speed/quality ratio

**Weaknesses:**
- Lower output token limit (6,536 tokens)
- May struggle with very long outputs

**Best For:** Planning, code review, architectural decisions

**Recommended Gentle-AI Role:** **Orchestrator** or **sdd-design** phase

---

### 2. Ling 3.0 Flash Fin Free (`ling-3.0-flash-fin-free`)
**Provider:** Alibaba | **Architecture:** Optimized for speed

**Strengths:**
- Very fast response times
- Large context window (262K)
- Excellent for batch processing
- Good at following structured formats

**Weaknesses:**
- May lack depth in complex reasoning
- Less creative in problem-solving

**Best For:** Documentation, routine code generation, simple tasks

**Recommended Gentle-AI Role:** **sdd-apply** or **sdd-tasks** phase

---

### 3. Nemotron 3 Ultra Free (`nemotron-3-ultra-free`)
**Provider:** NVIDIA | **Architecture:** Large-scale transformer

**Strengths:**
- Massive 1M context window (largest among free models)
- Strong technical capabilities
- Good at complex analysis
- Excellent code understanding

**Weaknesses:**
- Slower response times
- Higher resource usage

**Best For:** Complex code analysis, large codebase review, architecture

**Recommended Gentle-AI Role:** **sdd-explore** or **sdd-research** phase

---

### 4. Nemotron 3.5 Lightning Free (`nemotron-3.5-lightning-free`)
**Provider:** NVIDIA | **Architecture:** Optimized for speed

**Strengths:**
- Fast response times ("Lightning")
- Good balance of speed and quality
- 262K context window
- Good instruction following

**Weaknesses:**
- May not match Ultra in complex reasoning
- Newer model, less battle-tested

**Best For:** Quick iterations, code generation, routine tasks

**Recommended Gentle-AI Role:** **sdd-apply** or **sdd-verify** phase

---

### 5. Muse Spark 1.3 Contributor Free (`muse-spark-1.3-contributor-free`)
**Provider:** OpenCode | **Architecture:** Spark series

**Strengths:**
- Uses responses endpoint (newer API)
- Good for creative tasks
- Large output window (131K)
- Community-contributed model

**Weaknesses:**
- Less known provider/model
- May have inconsistent performance

**Best For:** Creative documentation, exploration, brainstorming

**Recommended Gentle-AI Role:** **sdd-explore** or documentation tasks

---

### 6. Big Pickle (`big-pickle`)
**Provider:** Stealth/Unknown | **Architecture:** Unknown

**Strengths:**
- Mystery model (possibly a frontier model in disguise)
- Full 262K context and output
- Community buzz suggests strong performance

**Weaknesses:**
- Unknown capabilities and limitations
- May be deprecated or changed

**Best For:** Experimental use, tasks where you want to test unknown capabilities

**Recommended Gentle-AI Role:** Testing/experimental only

---

### 7. DeepSeek V4 Flash Free (`deepseek-v4-flash-free`)
**Provider:** DeepSeek | **Architecture:** V4 Flash

**Strengths:**
- Strong code generation capabilities
- Good at following instructions
- Fast response times
- Excellent for coding tasks

**Weaknesses:**
- May not be as strong for non-code tasks
- Flash variant prioritizes speed

**Best For:** Code generation, implementation tasks

**Recommended Gentle-AI Role:** **sdd-apply** phase (implementation)

---

### 8. JEV 1.13 Free (`jev-1.13-free`)
**Provider:** Unknown | **Architecture:** Version 1.13

**Strengths:**
- Full context and output windows
- Available for free tier

**Weaknesses:**
- Limited information available
- Less community testing

**Best For:** Backup option, specific use cases

**Recommended Gentle-AI Role:** Alternative for any phase

## Gentle-AI SDD Phase Recommendations

### Recommended Model Assignments for Free Models

| SDD Phase | Recommended Model | Reason |
|-----------|-------------------|--------|
| **Orchestrator** (gentle-orchestrator) | `opencode/mimo-v2.5-free` | Best reasoning, good at delegation |
| **sdd-explore** | `opencode/nemotron-3-ultra-free` | 1M context for large codebases |
| **sdd-research** | `opencode/nemotron-3-ultra-free` | Deep analysis capabilities |
| **sdd-design** | `opencode/mimo-v2.5-free` | Strong architectural reasoning |
| **sdd-spec** | `opencode/ling-3.0-flash-fin-free` | Fast, good at structured output |
| **sdd-tasks** | `opencode/ling-3.0-flash-fin-free` | Fast task breakdown |
| **sdd-apply** | `opencode/deepseek-v4-flash-free` | Strong code generation |
| **sdd-verify** | `opencode/nemotron-3.5-lightning-free` | Fast verification checks |
| **sdd-archive** | `opencode/ling-3.0-flash-fin-free` | Fast documentation |

### Configuration Profile

Create a "free-models" profile in Gentle-AI:

```bash
# Create a profile using free models for all phases
gentle-ai sync --profile free-models:opencode/mimo-v2.5-free

# Override specific phases
gentle-ai sync \
  --profile free-models:opencode/mimo-v2.5-free \
  --profile-phase free-models:sdd-apply:opencode/deepseek-v4-flash-free \
  --profile-phase free-models:sdd-explore:opencode/nemotron-3-ultra-free \
  --profile-phase free-models:sdd-verify:opencode/nemotron-3.5-lightning-free
```

### OpenCode Configuration Example

Add to your `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "opencode": {
      "models": {
        "mimo-v2.5-free": { "name": "MiMo V2.5 Free", "tool_call": true },
        "nemotron-3-ultra-free": { "name": "Nemotron 3 Ultra Free", "tool_call": true },
        "nemotron-3.5-lightning-free": { "name": "Nemotron 3.5 Lightning Free", "tool_call": true },
        "ling-3.0-flash-fin-free": { "name": "Ling 3.0 Flash Free", "tool_call": true },
        "deepseek-v4-flash-free": { "name": "DeepSeek V4 Flash Free", "tool_call": true },
        "muse-spark-1.3-contributor-free": { "name": "Muse Spark 1.3 Free", "tool_call": true }
      }
    }
  }
}
```

## Privacy-Aware Model Selection

### The Problem
Free models come with hidden costs — **your data**. Not all providers handle your prompts and code the same way. Some train on your data, some log it for "improvement," and some are transparent about what they keep.

### Privacy Tiers

| Tier | Label | What It Means | Models |
|------|-------|---------------|--------|
| **1** | Strict Privacy | No data used for training. Zero-retention. No logging. | ❌ None available |
| **2** | Anonymous Improvement | Logged for improvement, NOT linked to identity. No model training. | Nemotron Ultra, Nemotron Lightning |
| **3** | Model Improvement | Data may be used to improve the model during free period. | MiMo, DeepSeek, Ling Flash, Big Pickle, JEV |
| **4** | Accept All | All models including those that train on your data. | Muse Spark (trains Meta models) |

### How It Works

1. **First-time setup**: Run `./privacy-setup.sh` to choose your privacy tier
2. **Persistent config**: Your preference is stored in `.privacy-config` — asked only once
3. **Automatic filtering**: `model-selector.sh` only shows/assigns models within your tier
4. **Change detection**: `check-model-changes.sh` monitors Zen for model additions/removals
5. **Re-evaluation**: When models change, your assignments are re-evaluated against your tier

### Quick Start

```bash
# 1. Set your privacy preference (first time only)
./privacy-setup.sh

# 2. See what models you have access to
./model-selector.sh list

# 3. Get recommended assignments for your tier
./model-selector.sh

# 4. Check if models have changed
./check-model-changes.sh
```

### Provider Privacy Evidence

| Provider | Claim | Source |
|----------|-------|--------|
| **NVIDIA (Nemotron)** | "Not designed to derive insights from personal data." Logged for improvement, not linked to identity. | [HuggingFace privacy.md](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-Base-BF16/blob/main/privacy.md) |
| **Xiaomi (MiMo)** | "Without prior consent, will not use text content for training." But Zen free tier has no opt-out. | [MiMo Privacy Policy](https://mimo.xiaomi.com/legal/privacy-policy) |
| **Alibaba (Ling)** | "Strictly protects data privacy and will never use your data for model training." But Zen intermediary policy applies. | [Alibaba Cloud Privacy](https://help.aliyun.com/en/model-studio/privacy-notice) |
| **DeepSeek** | "We may use your Inputs and Outputs to train and improve our models and services." | [DeepSeek Privacy](https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html) |
| **OpenCode Zen** | "Providers follow zero-retention... with exceptions: Big Pickle, MiMo, Ling Flash, Hy3 — data may be used to improve the model." | [OpenCode Zen Docs](https://opencode.ai/docs/zen) |
| **Meta (Muse Spark)** | "Permission to use your prompts and completions to train future Meta models." | [OpenCode Zen Docs](https://opencode.ai/docs/zen) |

### Modifying Preferences

```bash
# Change your privacy tier at any time
./privacy-setup.sh

# The system will re-evaluate all model assignments
# based on your new tier
```

## Key Considerations

### 1. Tool Calling Support
All listed free models support tool calling, which is **required** for Gentle-AI SDD phases. Without `tool_call: true`, models won't appear as selectable options in the model picker.

### 2. Rate Limits
Free models may have rate limits. Consider:
- Using faster models (Ling, Nemotron Lightning) for high-frequency phases
- Using stronger models (MiMo, Nemotron Ultra) for critical decision phases

### 3. Context Window Usage
- **1M context (Nemotron Ultra):** Use for large codebase exploration
- **262K context (most models):** Sufficient for most tasks
- **6K output (MiMo):** May need alternative for large code generation

### 4. Model Availability
These models are "available for a limited time." Monitor for:
- Deprecation notices
- New free model additions
- Performance changes

## Testing Strategy

### Phase 1: Baseline Testing
Test each model on:
1. Simple code generation task
2. Code review task
3. Documentation generation
4. Complex reasoning task

### Phase 2: Workflow Testing
Run complete SDD workflows with different model assignments:
1. All models same (baseline)
2. Optimized assignment (recommended above)
3. Cost-focused (cheapest/fastest only)

### Phase 3: Comparison Metrics
Measure:
- Response quality (1-5 scale)
- Response time
- Token usage
- Task completion rate
- Error rate

## Next Steps

1. **Initialize Gentle-AI in this project:**
   ```bash
   gga init
   gga install
   ```

2. **Create the free-models profile:**
   ```bash
   gentle-ai sync --profile free-models:opencode/mimo-v2.5-free
   ```

3. **Run test tasks** to validate model performance

4. **Adjust assignments** based on results

## Resources

- [Gentle-AI Documentation](https://github.com/Gentleman-Programming/gentle-ai)
- [OpenCode Zen Models](https://opencode.ai/docs/zen/)
- [SDD Profiles Guide](https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/opencode-profiles.md)
