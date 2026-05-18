# SATYA v1.0.0 — Release Notes

**Release Date:** May 18, 2026  
**Build:** Release APK (debug-signed for hackathon demo)

---

## What is SATYA?

SATYA (Sanskrit: सत्य, "truth") is an on-device truth detection app that uses Google's Gemma 4 to analyze images, text, and media for signs of manipulation, synthetic generation, or misinformation — entirely on your phone, with zero internet required for analysis.

---

## Installation

1. Download `app-release.apk` from the [Releases](https://github.com/something1703/satya/releases) page
2. Enable "Install from unknown sources" on your Android device
3. Install the APK
4. On first launch, SATYA will download the Gemma 4 model (~3.66 GB). This requires WiFi.
5. After download completes, the app works 100% offline.

---

## System Requirements

| Requirement | Minimum |
|---|---|
| Android Version | Android 10+ (API 26+) |
| RAM | 6 GB |
| Storage | 5 GB free (3.66 GB model + app) |
| Architecture | arm64-v8a only |
| Internet | Required only for first-time model download |

---

## Permissions

| Permission | Why |
|---|---|
| `INTERNET` | Download Gemma 4 model on first launch |
| `READ_MEDIA_IMAGES` | Access images for analysis |
| `READ_MEDIA_VIDEO` | Access videos for analysis |
| `CAMERA` | Future: live capture analysis |
| `WAKE_LOCK` | Keep device awake during inference |

---

## Privacy Statement

**SATYA runs 100% on-device.** No images, text, or analysis results are ever transmitted to any server. The Gemma 4 model runs locally using Google's LiteRT runtime. Your content never leaves your phone.

---

## Features in v1.0.0

- **Image Analysis**: Pick any image from gallery — analyzed for manipulation, deepfakes, and misleading content
- **Text Analysis**: Paste any claim, message, or URL — analyzed for misinformation patterns
- **Video Analysis**: Metadata-based analysis (frame-by-frame analysis coming in v2)
- **Share Intent**: Share content directly from WhatsApp, gallery, or any app to SATYA
- **Try Examples**: 3 pre-loaded Indian misinformation examples for instant demo
- **Structured Verdicts**: Color-coded results with confidence scores, evidence cards, and actionable recommendations
- **Function Calling**: Native Gemma 4 function calling ensures structured JSON output

---

## Fine-Tuned Model

The SATYA LoRA adapter is published at:  
**https://huggingface.co/rudrararaa/satya-gemma4-e4b-lora**

| Metric | Base Gemma 4 | SATYA Fine-Tuned | Improvement |
|---|---|---|---|
| Accuracy | 34.6% | 53.7% | **+19.1%** |
| F1 Score | 0.231 | 0.303 | **+0.072** |
| Schema Compliance | 95.9% | 98.9% | **+3.0%** |

---

## Known Limitations

- Video analysis uses metadata-only fallback (frame extraction planned for v2)
- Audio analysis limited to metadata (Gemma 4 E4B does not support audio natively)
- APK ships with base Gemma 4 model; fine-tuned LoRA is the published research artifact
- Debug-signed APK (not Play Store ready)

---

## Tech Stack

- **Model**: Gemma 4 E4B (4B parameters, on-device via LiteRT)
- **Fine-tuning**: Unsloth + LoRA on Indian fact-check dataset
- **Runtime**: Google LiteRT (Dart FFI)
- **Framework**: Flutter 3.32
- **Plugin**: flutter_gemma 0.15.2
