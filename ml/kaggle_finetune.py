# ============================================================================
# SATYA — Gemma 4 E4B Fine-Tuning with Unsloth (LoRA)
# ============================================================================
# Paste this entire script into a Kaggle notebook.
# Prerequisites:
#   - GPU T4 x2 enabled in Settings → Accelerator
#   - Kaggle Secrets: HF_TOKEN, HF_USERNAME
#   - Private dataset "SATYA Regional Fact-Check Data" added via Add Data
# ============================================================================

# %% — Install
!pip install -q "unsloth[kaggle]" datasets trl evaluate scikit-learn matplotlib

# %% — Imports
import json, os, csv, hashlib, random, warnings
from datetime import datetime
import numpy as np
import pandas as pd
from datasets import Dataset, load_dataset
from sklearn.metrics import (
    classification_report, confusion_matrix, accuracy_score, f1_score
)
import matplotlib.pyplot as plt

warnings.filterwarnings("ignore")

# %% — Auth
from kaggle_secrets import UserSecretsClient
from huggingface_hub import login

secrets = UserSecretsClient()
HF_TOKEN = secrets.get_secret("HF_TOKEN")
login(token=HF_TOKEN)

try:
    HF_USERNAME = secrets.get_secret("HF_USERNAME")
except Exception:
    HF_USERNAME = "satya-project"
    print(f"⚠ HF_USERNAME secret not found. Using default: {HF_USERNAME}")
    print("  Add it via Add-ons → Secrets → Label: HF_USERNAME, Value: your_username")

REPO_NAME = f"{HF_USERNAME}/satya-gemma4-e4b-lora"
print(f"Target HF repo: {REPO_NAME}")

# ============================================================================
# CONSTANTS
# ============================================================================

LABELS = ["LIKELY_AUTHENTIC", "INCONCLUSIVE", "LIKELY_MANIPULATED", "LIKELY_SYNTHETIC"]

SYSTEM_PROMPT = """You are a forensic media analyst specializing in detecting manipulated, synthetic, and misleading content. Your role is critical: people depend on your analysis before deciding whether to share content that could spread misinformation.

Analyze the provided content and call the submit_verdict function with a structured assessment. You must ALWAYS respond by calling the function — free-text responses are never acceptable.

For each piece of content, check for: visual manipulation (inconsistent lighting, warping, cloned regions), audio manipulation (unnatural prosody, spectral artifacts), and content manipulation (factual inconsistencies, misleading framing, emotional provocation).

Rules:
- Never assign confidence above 0.7 without at least two concrete pieces of evidence.
- Use INCONCLUSIVE honestly when uncertain.
- Cap evidence at 5 items.
- Always call submit_verdict. No free text."""

VERDICT_SCHEMA_STR = """{
  "name": "submit_verdict",
  "description": "Submit a structured truth-detection verdict for the analyzed content.",
  "parameters": {
    "type": "object",
    "required": ["schema_version","content_hash","overall_verdict","overall_confidence",
                  "category_scores","evidence","recommendation","explanation_short","explanation_detailed"],
    "properties": {
      "schema_version": {"type": "string", "enum": ["v1"]},
      "content_hash": {"type": "string"},
      "overall_verdict": {"type": "string", "enum": ["LIKELY_AUTHENTIC","INCONCLUSIVE","LIKELY_MANIPULATED","LIKELY_SYNTHETIC"]},
      "overall_confidence": {"type": "number", "minimum": 0.0, "maximum": 1.0},
      "category_scores": {"type": "array", "items": {"type": "object", "properties": {"category": {"type": "string"}, "confidence": {"type": "number"}}}},
      "evidence": {"type": "array", "maxItems": 5, "items": {"type": "object", "properties": {"type": {"type": "string"}, "description": {"type": "string"}, "location": {"type": "string"}}}},
      "recommendation": {"type": "string", "enum": ["SAFE_TO_FORWARD","VERIFY_BEFORE_FORWARDING","DO_NOT_FORWARD"]},
      "explanation_short": {"type": "string"},
      "explanation_detailed": {"type": "string"}
    }
  }
}"""

CONFIDENCE_MAP = {
    "LIKELY_MANIPULATED": 0.85,
    "LIKELY_AUTHENTIC": 0.85,
    "LIKELY_SYNTHETIC": 0.85,
    "INCONCLUSIVE": 0.55,
}

RECOMMENDATION_MAP = {
    "LIKELY_MANIPULATED": "DO_NOT_FORWARD",
    "LIKELY_SYNTHETIC": "DO_NOT_FORWARD",
    "INCONCLUSIVE": "VERIFY_BEFORE_FORWARDING",
    "LIKELY_AUTHENTIC": "SAFE_TO_FORWARD",
}

LIAR_LABEL_MAP = {
    0: "LIKELY_MANIPULATED",  # pants-fire
    1: "LIKELY_MANIPULATED",  # false
    2: "INCONCLUSIVE",        # barely-true
    3: "INCONCLUSIVE",        # half-true
    4: "LIKELY_AUTHENTIC",    # mostly-true
    5: "LIKELY_AUTHENTIC",    # true
}

# ============================================================================
# 1. LOAD DATASETS
# ============================================================================

# %% — Load regional dataset
print("📥 Loading regional dataset...")
REGIONAL_CSV = "/kaggle/input/datasets/rudrararaa/satya-regional-fact-check-data/regional_factchecks.csv"
df_regional = pd.read_csv(REGIONAL_CSV)
print(f"   Loaded {len(df_regional)} rows from regional CSV")
print(f"   Distribution:\n{df_regional['rating_normalized'].value_counts().to_string()}\n")

# %% — Load LIAR dataset
print("📥 Loading LIAR dataset...")
liar_ds = load_dataset("chengxuphd/liar2")
# Combine all splits for maximum data
# LIAR labels are integers — get the string names from dataset features
liar_rows = []
for split_name in ["train", "validation", "test"]:
    if split_name not in liar_ds:
        continue
    for row in liar_ds[split_name]:
        raw_label = row.get("label")
        if raw_label is None:
            continue
        mapped = LIAR_LABEL_MAP.get(int(raw_label))
        if mapped is None:
            continue
        liar_rows.append({
            "statement": row.get("statement", ""),
            "speaker": row.get("speaker", ""),
            "subject": row.get("subject", ""),
            "context": row.get("context", ""),
            "label_mapped": mapped,
        })
    

df_liar = pd.DataFrame(liar_rows)
print(f"   Loaded {len(df_liar)} rows from LIAR")
print(f"   Distribution:\n{df_liar['label_mapped'].value_counts().to_string()}\n")

# ============================================================================
# 2. BALANCE CLASSES
# ============================================================================

# %% — Balance
print("🔀 Balancing classes...")
random.seed(42)
np.random.seed(42)

# Regional: downsample LIKELY_MANIPULATED to 2500, keep rest as-is
regional_manip = df_regional[df_regional["rating_normalized"] == "LIKELY_MANIPULATED"].sample(
    n=min(2500, len(df_regional[df_regional["rating_normalized"] == "LIKELY_MANIPULATED"])),
    random_state=42
)
regional_other = df_regional[df_regional["rating_normalized"] != "LIKELY_MANIPULATED"]
df_regional_balanced = pd.concat([regional_manip, regional_other], ignore_index=True)
print(f"   Regional after balancing: {len(df_regional_balanced)}")
print(f"   {df_regional_balanced['rating_normalized'].value_counts().to_string()}\n")

# LIAR: sample to fill class gaps
liar_auth = df_liar[df_liar["label_mapped"] == "LIKELY_AUTHENTIC"].sample(
    n=min(2000, len(df_liar[df_liar["label_mapped"] == "LIKELY_AUTHENTIC"])), random_state=42
)
liar_incon = df_liar[df_liar["label_mapped"] == "INCONCLUSIVE"].sample(
    n=min(2000, len(df_liar[df_liar["label_mapped"] == "INCONCLUSIVE"])), random_state=42
)
liar_manip = df_liar[df_liar["label_mapped"] == "LIKELY_MANIPULATED"].sample(
    n=min(1500, len(df_liar[df_liar["label_mapped"] == "LIKELY_MANIPULATED"])), random_state=42
)
df_liar_balanced = pd.concat([liar_auth, liar_incon, liar_manip], ignore_index=True)
print(f"   LIAR after balancing: {len(df_liar_balanced)}")
print(f"   {df_liar_balanced['label_mapped'].value_counts().to_string()}\n")

# ============================================================================
# 3. CONVERT TO FUNCTION-CALLING FORMAT
# ============================================================================

# %% — Conversion helpers
def content_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]

def build_verdict_json(label, claim_text, evidence_items, publisher="", original_rating=""):
    conf = CONFIDENCE_MAP[label]
    rec = RECOMMENDATION_MAP[label]
    cat = label.lower().replace("likely_", "")

    if publisher:
        short = f"This claim was reviewed by {publisher} and rated as {original_rating.lower()}."
        detailed = f"This claim was reviewed by {publisher} and rated as {original_rating.lower()}. Based on the fact-checker's assessment, this content is classified as {label.replace('_', ' ').lower()}."
    else:
        short = f"This claim is classified as {label.replace('_', ' ').lower()} based on available evidence."
        detailed = f"Analysis of this claim suggests it is {label.replace('_', ' ').lower()}. Verification through additional sources is recommended before sharing."

    return json.dumps({
        "schema_version": "v1",
        "content_hash": f"sha256_{content_hash(claim_text)}",
        "overall_verdict": label,
        "overall_confidence": conf,
        "category_scores": [{"category": cat, "confidence": conf}],
        "evidence": evidence_items[:5],
        "recommendation": rec,
        "explanation_short": short,
        "explanation_detailed": detailed,
    }, indent=2)

def regional_to_messages(row):
    claim = str(row.get("claim_text", "")).strip()
    label = str(row.get("rating_normalized", "INCONCLUSIVE"))
    claimant = str(row.get("claimant", "Unknown"))
    publisher = str(row.get("publisher", "Unknown"))
    rating = str(row.get("rating", ""))
    url = str(row.get("review_url", ""))

    user_msg = (
        f"Analyze this claim circulated in Indian social media:\n\n"
        f"\"{claim}\"\n\n"
        f"Claimant: {claimant}\n"
        f"Fact-checker: {publisher}"
    )

    evidence = [{"type": "fact_check_finding",
                 "description": f"Fact-checked by {publisher}: claim rated {rating}",
                 "location": f"Source: {url}"}]

    verdict_json = build_verdict_json(label, claim, evidence, publisher, rating)
    assistant_msg = f"<tool_call>\nsubmit_verdict({verdict_json})\n</tool_call>"

    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT + f"\n\n## Available Function\n{VERDICT_SCHEMA_STR}"},
            {"role": "user", "content": user_msg},
            {"role": "assistant", "content": assistant_msg},
        ],
        "label": label,
    }

def liar_to_messages(row):
    statement = str(row.get("statement", "")).strip()
    label = str(row.get("label_mapped", "INCONCLUSIVE"))
    speaker = str(row.get("speaker", "Unknown"))
    subject = str(row.get("subject", ""))
    context = str(row.get("context", ""))

    user_msg = (
        f"Analyze this political claim:\n\n"
        f"\"{statement}\"\n\n"
        f"Context: {subject}\n"
        f"Speaker: {speaker}"
    )

    evidence = [{"type": "political_claim_analysis",
                 "description": f"Claim by {speaker} on subject: {subject}",
                 "location": f"Context: {context[:200]}"}]

    verdict_json = build_verdict_json(label, statement, evidence)
    assistant_msg = f"<tool_call>\nsubmit_verdict({verdict_json})\n</tool_call>"

    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT + f"\n\n## Available Function\n{VERDICT_SCHEMA_STR}"},
            {"role": "user", "content": user_msg},
            {"role": "assistant", "content": assistant_msg},
        ],
        "label": label,
    }

# %% — Convert all examples
print("📝 Converting to function-calling format...")

all_examples = []
for _, row in df_regional_balanced.iterrows():
    all_examples.append(regional_to_messages(row))
for _, row in df_liar_balanced.iterrows():
    all_examples.append(liar_to_messages(row))

random.shuffle(all_examples)

total = len(all_examples)
train_end = int(total * 0.85)
val_end = int(total * 0.95)

train_data = all_examples[:train_end]
val_data = all_examples[train_end:val_end]
test_data = all_examples[val_end:]

print(f"   Total: {total} | Train: {len(train_data)} | Val: {len(val_data)} | Test: {len(test_data)}")

label_counts = {}
for ex in all_examples:
    label_counts[ex["label"]] = label_counts.get(ex["label"], 0) + 1
print(f"   Label distribution: {label_counts}\n")

# ============================================================================
# 4. LOAD MODEL AND APPLY LoRA
# ============================================================================

# %% — Load model
print("🤖 Loading Gemma 4 E4B with 4-bit quantization...")
from unsloth import FastLanguageModel

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="google/gemma-4-e4b-it",
    max_seq_length=4096,
    dtype=None,
    load_in_4bit=True,
)

# %% — Apply LoRA
print("🧠 Applying LoRA adapters...")
model = FastLanguageModel.get_peft_model(
    model,
    r=16,
    lora_alpha=32,
    lora_dropout=0.0,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                     "gate_proj", "up_proj", "down_proj"],
    bias="none",
    use_gradient_checkpointing="unsloth",
)

# ============================================================================
# 5. TRAIN
# ============================================================================

# %% — Prepare datasets for SFTTrainer
def format_chat(example):
    return tokenizer.apply_chat_template(
        example["messages"], tokenize=False, add_generation_prompt=False
    )

train_ds = Dataset.from_list([{"messages": ex["messages"]} for ex in train_data]).map(
    lambda x: {"text": format_chat(x)}, remove_columns=["messages"]
)
val_ds = Dataset.from_list([{"messages": ex["messages"]} for ex in val_data]).map(
    lambda x: {"text": format_chat(x)}, remove_columns=["messages"]
)

# %% — Train
print("🏋️ Starting training (estimated 6-10 hours)...")
from trl import SFTTrainer, SFTConfig

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=train_ds,
    eval_dataset=val_ds,
    args=SFTConfig(
        per_device_train_batch_size=2,
        gradient_accumulation_steps=8,
        warmup_ratio=0.05,
        num_train_epochs=3,
        learning_rate=2e-4,
        fp16=True,
        logging_steps=25,
        eval_strategy="steps",
        eval_steps=200,
        save_strategy="steps",
        save_steps=500,
        output_dir="satya-lora-checkpoints",
        report_to="none",
        dataset_text_field="text",
        max_seq_length=4096,
    ),
)

trainer.train()
print("✅ Training complete!\n")

# ============================================================================
# 6. EVALUATION
# ============================================================================

# %% — Evaluation helper
def run_eval(eval_model, eval_tokenizer, test_examples, model_name="model"):
    """Run inference on test set and return predictions + ground truths."""
    print(f"   Evaluating {model_name} on {len(test_examples)} examples...")
    FastLanguageModel.for_inference(eval_model)

    preds = []
    truths = []

    for i, ex in enumerate(test_examples):
        gt_label = ex["label"]

        prompt = eval_tokenizer.apply_chat_template(
            ex["messages"][:2],  # system + user only
            tokenize=False,
            add_generation_prompt=True,
        )
        inputs = eval_tokenizer(prompt, return_tensors="pt").to(eval_model.device)
        outputs = eval_model.generate(**inputs, max_new_tokens=1024, temperature=0.3,
                                       do_sample=False)
        response = eval_tokenizer.decode(outputs[0][inputs.input_ids.shape[1]:],
                                          skip_special_tokens=True)

        # Parse verdict from response
        pred_label = "PARSE_ERROR"
        try:
            # Find JSON in response
            brace_start = response.index("{")
            depth = 0
            for j in range(brace_start, len(response)):
                if response[j] == "{": depth += 1
                if response[j] == "}": depth -= 1
                if depth == 0:
                    json_str = response[brace_start:j+1]
                    parsed = json.loads(json_str)
                    pred_label = parsed.get("overall_verdict", "PARSE_ERROR")
                    break
        except (ValueError, json.JSONDecodeError):
            pred_label = "PARSE_ERROR"

        if pred_label not in LABELS:
            pred_label = "PARSE_ERROR"

        preds.append(pred_label)
        truths.append(gt_label)

        if (i + 1) % 50 == 0:
            print(f"      Processed {i+1}/{len(test_examples)}")

    return preds, truths

def compute_metrics(preds, truths, model_name):
    """Compute accuracy, F1, and confusion matrix. Return dict of metrics."""
    # Filter out parse errors for fair comparison
    valid = [(p, t) for p, t in zip(preds, truths) if p != "PARSE_ERROR"]
    parse_errors = len(preds) - len(valid)
    if not valid:
        return {"accuracy": 0, "f1_macro": 0, "parse_errors": parse_errors}

    vp, vt = zip(*valid)
    acc = accuracy_score(vt, vp)
    f1 = f1_score(vt, vp, labels=LABELS, average="macro", zero_division=0)
    schema_compliance = len(valid) / len(preds) * 100

    print(f"\n   === {model_name} Results ===")
    print(f"   Accuracy: {acc:.4f}")
    print(f"   F1 (macro): {f1:.4f}")
    print(f"   Schema compliance: {schema_compliance:.1f}% ({parse_errors} parse errors)")
    print(f"\n{classification_report(vt, vp, labels=LABELS, zero_division=0)}")

    return {
        "accuracy": acc,
        "f1_macro": f1,
        "parse_errors": parse_errors,
        "schema_compliance": schema_compliance,
        "report": classification_report(vt, vp, labels=LABELS, zero_division=0, output_dict=True),
    }

# %% — Evaluate fine-tuned model
print("📊 Evaluating fine-tuned model...")
ft_preds, ft_truths = run_eval(model, tokenizer, test_data, "SATYA Fine-Tuned")
ft_metrics = compute_metrics(ft_preds, ft_truths, "SATYA Fine-Tuned")

# %% — Evaluate base model for comparison
print("\n📊 Evaluating base model for comparison...")
print("   Reloading base Gemma 4 E4B without LoRA...")

base_model, base_tokenizer = FastLanguageModel.from_pretrained(
    model_name="google/gemma-4-e4b-it",
    max_seq_length=4096,
    dtype=None,
    load_in_4bit=True,
)

base_preds, base_truths = run_eval(base_model, base_tokenizer, test_data, "Base Gemma 4 E4B")
base_metrics = compute_metrics(base_preds, base_truths, "Base Gemma 4 E4B")

# %% — Comparison
acc_diff = ft_metrics["accuracy"] - base_metrics["accuracy"]
f1_diff = ft_metrics["f1_macro"] - base_metrics["f1_macro"]

print("\n" + "═" * 56)
print(f"{'BASE GEMMA 4 E4B':<24}| Acc: {base_metrics['accuracy']:.4f} | F1: {base_metrics['f1_macro']:.4f}")
print(f"{'SATYA FINE-TUNED':<24}| Acc: {ft_metrics['accuracy']:.4f} | F1: {ft_metrics['f1_macro']:.4f}")
print(f"{'IMPROVEMENT':<24}| {acc_diff:+.4f}     | {f1_diff:+.4f}")
print("═" * 56)

if acc_diff < 0.05:
    print("\n⚠ WARNING: Accuracy improvement is below +5%.")
    print("  Consider retraining with different hyperparameters or more data.")

# ============================================================================
# 7. SAVE RESULTS
# ============================================================================

# %% — Save eval results
eval_md = f"""# SATYA Fine-Tuning Evaluation Results

**Date:** {datetime.now().isoformat()}
**Base Model:** google/gemma-4-e4b-it
**Method:** LoRA (rank 16, alpha 32, dropout 0.05) via Unsloth
**Regional examples:** {len(df_regional_balanced)}
**LIAR examples:** {len(df_liar_balanced)}
**Total training examples:** {len(train_data)}
**Test examples:** {len(test_data)}

## Results

| Metric | Base Gemma 4 E4B | SATYA Fine-Tuned | Improvement |
|--------|-----------------|------------------|-------------|
| Accuracy | {base_metrics['accuracy']:.4f} | {ft_metrics['accuracy']:.4f} | {acc_diff:+.4f} |
| F1 (macro) | {base_metrics['f1_macro']:.4f} | {ft_metrics['f1_macro']:.4f} | {f1_diff:+.4f} |
| Schema Compliance | {base_metrics['schema_compliance']:.1f}% | {ft_metrics['schema_compliance']:.1f}% | — |
| Parse Errors | {base_metrics['parse_errors']} | {ft_metrics['parse_errors']} | — |

## Training Hyperparameters

| Parameter | Value |
|-----------|-------|
| LoRA rank | 16 |
| LoRA alpha | 32 |
| LoRA dropout | 0.05 |
| Learning rate | 2e-4 |
| Epochs | 3 |
| Batch size | 2 |
| Gradient accumulation | 8 |
| Max seq length | 4096 |

## Data Sources

| Source | Examples | Notes |
|--------|----------|-------|
| Regional Fact-Checks (Boom, Alt News, etc.) | {len(df_regional_balanced)} | Indian social media claims |
| LIAR Political Claims | {len(df_liar_balanced)} | US political fact-checks |
"""

with open("/kaggle/working/eval_results.md", "w") as f:
    f.write(eval_md)
print("\n📄 Evaluation saved to /kaggle/working/eval_results.md")

# ============================================================================
# 8. PUSH TO HUGGING FACE
# ============================================================================

# %% — Push
print(f"\n☁️ Pushing to Hugging Face: {REPO_NAME}...")

model.save_pretrained("satya-lora-adapter")
tokenizer.save_pretrained("satya-lora-adapter")

# Write model card
model_card = f"""---
license: apache-2.0
base_model: google/gemma-4-e4b-it
tags:
  - satya
  - fact-checking
  - misinformation-detection
  - lora
  - unsloth
datasets:
  - liar
  - custom
language:
  - en
  - hi
---

# SATYA — Fine-Tuned Gemma 4 E4B for Truth Detection

LoRA adapter fine-tuned on {total} fact-checking examples for on-device misinformation detection.

## Base Model
google/gemma-4-e4b-it (4-bit quantized)

## Training Data
- **{len(df_regional_balanced)}** regional Indian fact-checks (Boom Live, Alt News, FACTLY, The Quint, Vishvas News, etc.)
- **{len(df_liar_balanced)}** political claims from the LIAR dataset

## Results

| Metric | Base | Fine-Tuned | Improvement |
|--------|------|-----------|-------------|
| Accuracy | {base_metrics['accuracy']:.4f} | {ft_metrics['accuracy']:.4f} | {acc_diff:+.4f} |
| F1 (macro) | {base_metrics['f1_macro']:.4f} | {ft_metrics['f1_macro']:.4f} | {f1_diff:+.4f} |

## Intended Use
On-device truth detection in the SATYA mobile app. Classifies content into:
LIKELY_AUTHENTIC, INCONCLUSIVE, LIKELY_MANIPULATED, LIKELY_SYNTHETIC

## Limitations
- Trained primarily on text claims; visual/audio deepfake detection requires additional modalities
- Regional bias toward Indian English-language fact-checks
- Not a replacement for professional fact-checking

## License
Apache 2.0
"""

with open("satya-lora-adapter/README.md", "w") as f:
    f.write(model_card)

model.push_to_hub(REPO_NAME, token=HF_TOKEN)
tokenizer.push_to_hub(REPO_NAME, token=HF_TOKEN)

print(f"\n✅ Done! Adapter live at: https://huggingface.co/{REPO_NAME}")
print(f"   Download eval_results.md from /kaggle/working/ and copy to ml/eval/results.md")
