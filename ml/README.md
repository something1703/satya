# SATYA — ML Fine-Tuning Guide

## Quick Start (Step by Step)

### Step 1: Go to Kaggle
1. Open [kaggle.com/code](https://www.kaggle.com/code) and click **"New Notebook"**
2. Go to **Settings** (right sidebar) → **Accelerator** → Select **"GPU T4 x2"**

### Step 2: Add Your HuggingFace Token
1. In the notebook sidebar, click **"Add-ons"** → **"Secrets"**
2. Add a new secret:
   - **Label:** `HF_TOKEN`
   - **Value:** Your HuggingFace token with WRITE access

### Step 3: Paste the Script
1. Open `ml/kaggle_finetune.py` from this project
2. Copy the entire contents
3. Paste into a single cell in your Kaggle notebook

### Step 4: Run
1. Click **"Run All"** (or Ctrl+Shift+Enter)
2. Wait 6-10 hours. The script will:
   - Download Gemma 4 E4B (4-bit quantized)
   - Build training data with deepfake/misinformation examples
   - Fine-tune using LoRA adapters
   - Evaluate and print results
   - Push the adapter to HuggingFace

### Step 5: After Training
1. Download `eval_results.md` from Kaggle output
2. Copy it to `ml/eval/results.md` in this project
3. Your LoRA adapter is now live on HuggingFace!

## How It Connects to the Mobile App
1. The LoRA adapter gets merged into the base Gemma 4 model
2. The merged model is converted to `.litertlm` format
3. We update `app_config.dart` to point to the new model URL
4. Users download YOUR custom model instead of the base model

## Files
| File | Purpose |
|------|---------|
| `kaggle_finetune.py` | The complete training script |
| `verdict_schema.json` | JSON schema used in training prompts |
| `eval/results.md` | Evaluation results (filled after training) |
| `ollama/Modelfile` | Ollama config for desktop demo |
