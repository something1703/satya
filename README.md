# SATYA — On-Device Truth Detection Powered by Gemma 4

> *सत्य · Sanskrit for "truth"*

A privacy-first Android application that detects manipulated media — deepfakes, AI-generated images, synthetic audio, and misinformation — entirely on-device using Gemma 4, with cryptographically verifiable verdicts that anyone can independently check.

**Hackathon:** Gemma 4 Good Hackathon · Kaggle
**Deadline:** May 18, 2026 · 23:59 UTC
**Tracks targeted:** Main Track · Safety & Trust · Unsloth · Ollama
**Total prize target:** $80,000
**Team size:** 5

---

## 0. Read This First — Operating Instructions for the AI Agent

You are an AI coding agent. You will build this project under the direction of the human user. Follow these rules without exception:

**Sequencing.** Build phases run in strict order. Do not start `PHASE_2` until `PHASE_1` checkpoints pass. Do not start `PHASE_3` until `PHASE_2` checkpoints pass.

**No improvisation.** If the plan says "use Flutter," do not switch to React Native because you think it's better. If you genuinely believe a change is needed, stop and ask the user with reasoning. Wait for explicit approval.

**No skipped steps.** Every step in every phase has a purpose. Some steps look optional — they are not.

**Verification before progress.** Every phase ends with a checkpoint. Run it. If it fails, stop and debug. Do not paper over failures.

**Human-in-the-loop steps.** When a task requires the human to do something a script cannot — create an account, accept a license, paste an API key, scan a QR code — output a clearly labeled block:

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. ...
  2. ...
URL (if applicable):
  https://...
What you need to give me back when done:
  - API key
  - Confirmation that step X is complete
Reason this is needed:
  ...
```

Then **stop and wait**. Do not continue until the human confirms.

**Commit hygiene.** After every meaningful step, commit to git with a descriptive message. Push to the public repository (set up in Phase 1).

**Documentation.** Update the README's "Build Log" section at the end of every working session with what was completed.

---

## 1. The Problem

Misinformation is not abstract. In India alone:
- WhatsApp-driven lynchings killed dozens of people between 2017–2018
- COVID-19 misinformation led to deaths from unverified treatments
- 2024 election cycles saw a documented 900% increase in AI-generated political deepfakes
- 500 million WhatsApp users receive hundreds of forwards daily, most unverified

Existing fact-checkers are slow, centralized, English-first, and unavailable to the people who need them most. Cloud AI cannot solve this because:

- Forwarding private WhatsApp content to Google servers violates user privacy
- API costs make free, mass-deployment impossible
- Latency makes real-time detection unusable
- Centralized fact-checking is itself a trust problem — who fact-checks the fact-checkers?

We need a tool that lives in the user's pocket, never sends their content anywhere, costs nothing to run, and produces verdicts that cannot be faked even by the developer.

---

## 2. The Solution

SATYA is an Android application where the user shares any suspicious content into the app — a video, image, audio clip, or forwarded message — and receives within seconds a structured verdict:

- **Manipulation confidence score** (0–100)
- **Specific evidence** ("facial inconsistency at frame 14", "audio-visual sync break at 0:08")
- **Context** ("earliest known version of this clip dates to 2019")
- **Recommendation** ("do not forward")

The entire analysis runs on the user's phone using Gemma 4 E4B. No content ever leaves the device.

Each verdict is cryptographically signed by the analyzing device using a locally generated Ed25519 keypair. The signed verdict (containing only the content hash and the verdict, never the content itself) is published to a federated verdict cache. When another user encounters the same content, they instantly see the existing verdict without re-analyzing — and the signature proves no central party fabricated it.

This produces a **crowd-verified truth layer** that grows stronger as more people use it, without ever centralizing content or trust.

---

## 3. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    USER'S ANDROID DEVICE                     │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Flutter App — single-screen UI                        │ │
│  │  Share-target receives content from WhatsApp etc.      │ │
│  └────────────────────┬───────────────────────────────────┘ │
│                       │                                     │
│  ┌────────────────────▼───────────────────────────────────┐ │
│  │  Verdict Cache Lookup                                  │ │
│  │  1. Compute SHA-256 of content                         │ │
│  │  2. Query federated cache: "any verdicts for hash X?"  │ │
│  │  3. If yes → display existing verdicts + consensus     │ │
│  │  4. If no → run local analysis                         │ │
│  └────────────────────┬───────────────────────────────────┘ │
│                       │                                     │
│  ┌────────────────────▼───────────────────────────────────┐ │
│  │  Analysis Engine (Gemma 4 E4B via flutter_gemma)       │ │
│  │  • Multimodal: video frames + audio + text together    │ │
│  │  • Fine-tuned LoRA adapter for manipulation detection  │ │
│  │  • Function-calling output: structured verdict JSON    │ │
│  │  • Thinking mode for evidence reasoning                │ │
│  └────────────────────┬───────────────────────────────────┘ │
│                       │                                     │
│  ┌────────────────────▼───────────────────────────────────┐ │
│  │  Signing & Publishing                                  │ │
│  │  • Ed25519 keypair generated on first launch           │ │
│  │  • Sign {content_hash, verdict, timestamp, device_id}  │ │
│  │  • POST to verdict cache backend                       │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│            FEDERATED VERDICT CACHE (Firebase)                │
│                                                              │
│  Stores: { content_hash → [signed verdicts from devices] }  │
│  Anyone can query by content hash                            │
│  Anyone can verify signatures against public keys            │
│  No central authority can fabricate verdicts                 │
│  No private content is ever stored — only hashes + verdicts  │
└─────────────────────────────────────────────────────────────┘
```

**Why this design beats blockchain for our use case:** Same cryptographic guarantees (verdicts cannot be forged, anyone can verify), but with zero gas fees, instant lookups, and no wallet setup required by users. We get the trust properties without the friction. The signature scheme is exactly what underlies Sigstore (the industry-standard supply chain security model used by major tech companies).

---

## 4. Why Gemma 4 Specifically

| Requirement | Why Cloud AI Fails | Why Gemma 4 Wins |
|---|---|---|
| Privacy | Cannot send private WhatsApp content to a Google server | 100% on-device inference |
| Cost | API costs at hundreds of millions of users = unsustainable | Open weights, zero inference cost |
| Latency | Cloud round-trip is too slow for real-time forwarding decisions | E4B inference under 5 seconds locally |
| Multimodal | Most models handle text OR image OR audio separately | Gemma 4 handles all natively in one inference |
| Offline | Misinformation spreads fastest when networks are congested | Works fully offline |
| Customization | Cannot fine-tune GPT-4 for regional misinformation patterns | Unsloth LoRA fine-tuning on regional dataset |
| License | API terms forbid building competing products | Apache 2.0 — fully permissive |

**Specific Gemma 4 features used:**
- **Native multimodal** — single inference processes video frames + audio waveform + text together
- **Thinking mode** — chain-of-thought reasoning explains *why* something was flagged, building trust
- **Function calling** — structured JSON verdict output enforced natively
- **128k context window** — entire forwarded message thread plus reference cache loaded in one pass
- **Native audio input on E4B** — voice synthesis detection without a separate speech-to-text step
- **Apache 2.0 licensing** — fine-tuned weights legally publishable

---

## 5. Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| Mobile framework | Flutter (Dart) | Past winner GemmaVision used Flutter, `flutter_gemma` package has best Gemma support |
| On-device LLM | Gemma 4 E4B | 4GB RAM footprint, native multimodal, runs on mid-range phones |
| LLM runtime | `flutter_gemma` (Google AI Edge MediaPipe GenAI) | Officially supported, GPU-accelerated |
| Fine-tuning | Unsloth + LoRA | Hits Unsloth Special Tech prize; 5x faster than HF Transformers |
| Training compute | Kaggle Notebooks (free T4/P100 GPU) | Free, generous compute, hackathon-allowed |
| Local serving (dev) | Ollama | Hits Ollama Special Tech prize; easy local dev |
| Verdict cache | Firebase Firestore + Firebase Functions | Free tier handles 50K reads/day, no infra to manage |
| Cryptographic signatures | Ed25519 via `cryptography` (Dart) | Industry standard, fast, tiny key size |
| Content hashing | SHA-256 | Standard, fast, collision-resistant |
| Frame extraction | `ffmpeg_kit_flutter` | Reliable cross-platform video processing |
| App distribution | Direct APK via GitHub Releases + Play Store internal testing | Hackathon needs public download link |
| Model hosting | Hugging Face | Required for publishing fine-tuned weights |
| Landing page | Vercel + Next.js (static) | Free, fast deploy |
| Code repo | GitHub (public) | Required for hackathon submission |

---

## 6. Team Roles

| Member | Phase 1 ownership | Phase 2 ownership | Phase 3 ownership |
|---|---|---|---|
| ML / Fine-tuning | Set up Kaggle GPU, download Gemma 4 weights | Build fine-tuning pipeline with Unsloth, publish weights | Benchmarks, evaluation, writeup technical section |
| Agentic AI | Design analysis pipeline architecture | Build multimodal analysis engine, function calling, prompt engineering | Integration testing, edge cases |
| App Developer | Flutter project init, on-device Gemma 4 inference working | Full app UI, share-target intent, camera/gallery integration | Final polish, APK build, Play Store internal release |
| Full-stack | Firebase project, verdict cache schema | Cloud Functions for verdict storage and aggregation, signature verification API | Landing page, demo deployment |
| Crypto / Security | Ed25519 keypair generation and storage in app | Signing flow, verdict serialization format | Demo video production support, writeup |

---

## 7. Build Phases Overview

### Phase 1 — Foundation (Days 1–2)
**File:** `PHASE_1_FOUNDATION.md`
- All accounts and services created
- Flutter project initialized and committed to GitHub
- Gemma 4 E4B downloaded and running locally on a real Android phone
- Basic "Hello Gemma" inference verified end-to-end
- Firebase project created and connected

### Phase 2 — Core Engine (Days 3–6)
**File:** `PHASE_2_CORE_ENGINE.md`
- Multimodal analysis pipeline functional (video + audio + text)
- Fine-tuning pipeline running on Kaggle, LoRA adapter trained
- Full Android app UI built with share-target support
- Verdict JSON schema finalized and enforced via function calling
- App can analyze a video and produce a structured verdict end-to-end

### Phase 3 — Verification & Ship (Days 7–9)
**File:** `PHASE_3_VERIFICATION_AND_SHIP.md`
- Ed25519 signing of verdicts working
- Firebase verdict cache live with deduplication
- Signature verification on the device working
- End-to-end demo: receive WhatsApp forward → analyze → see verdict → share verdict back
- Demo video shot and edited
- Kaggle writeup completed
- Public APK released
- Submission filed

---

## 8. Project Structure

```
satya/
├── README.md                          # this file
├── docs/
│   ├── PHASE_1_FOUNDATION.md
│   ├── PHASE_2_CORE_ENGINE.md
│   ├── PHASE_3_VERIFICATION_AND_SHIP.md
│   └── BUILD_LOG.md                   # daily progress log
├── mobile/                            # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── analysis/                  # Gemma 4 inference + multimodal
│   │   ├── crypto/                    # Ed25519 signing
│   │   ├── ui/                        # screens and widgets
│   │   └── verdict_cache/             # Firebase client
│   ├── android/
│   ├── ios/
│   ├── pubspec.yaml
│   └── assets/
│       └── models/                    # Gemma 4 model file (not committed)
├── ml/                                # Fine-tuning
│   ├── unsloth_finetune.ipynb         # main fine-tuning notebook
│   ├── dataset/                       # training data
│   ├── eval/                          # evaluation scripts
│   └── README.md
├── backend/                           # Firebase Functions
│   ├── functions/
│   │   ├── index.ts                   # Cloud Functions entry
│   │   ├── verdict_store.ts
│   │   └── signature_verify.ts
│   ├── firestore.rules
│   └── firebase.json
├── landing/                           # Next.js landing page
│   ├── pages/
│   └── package.json
├── video/                             # demo video assets
│   ├── script.md
│   ├── shot_list.md
│   └── final.mp4
├── kaggle_writeup.md                  # final hackathon writeup
└── .github/
    └── workflows/                     # CI for app builds
```

---

## 9. Submission Deliverables Checklist

Per Kaggle hackathon rules, every submission requires:

- [ ] **Kaggle Writeup** (max 1500 words) — `kaggle_writeup.md`
- [ ] **Public GitHub repository** — code, well-documented, Apache 2.0 licensed
- [ ] **Public YouTube video** (max 3 minutes) — demo with the human story
- [ ] **Live demo** — public APK download link via GitHub Releases
- [ ] **Cover image** for Kaggle writeup
- [ ] **Published fine-tuned weights** on Hugging Face (for Unsloth prize)
- [ ] **Benchmark results** for fine-tuned model (Unsloth prize requirement)
- [ ] **Ollama Modelfile** if running locally via Ollama (Ollama prize requirement)

---

## 10. Success Criteria — How We Know We Won

A submission is hackathon-grade if:

- A real person who has never seen the app can install the APK, share a video into it, and receive a meaningful verdict in under 30 seconds
- The fine-tuned model demonstrably outperforms base Gemma 4 on a held-out misinformation detection benchmark (published numbers, not vibes)
- The same content analyzed on two different devices produces verdicts that match within 5% confidence
- The demo video makes a non-technical viewer say "I need this app on my phone right now"
- The code repository can be cloned and built from scratch by following the README, with no missing pieces

---

## 11. Build Log

| Date | What was completed |
|---|---|
| May 15 | Phase 1 complete: Flutter project, Firebase, Gemma 4 on-device inference verified |
| May 16 | Phase 2 core: Multimodal pipeline (image bytes), verdict schema, analyzing/verdict UI screens |
| May 17 | Fine-tuning: LoRA training on Kaggle T4×2 (10K examples, Indian fact-check + LIAR datasets) |
| May 17 | Function calling: GemmaService with Tool/ToolChoice.required, submit_verdict schema |
| May 17 | Share intent: receive_sharing_intent wired in main.dart + AndroidManifest |
| May 18 | Fine-tune eval: +19.1% accuracy, 98.9% schema compliance. Published to HuggingFace |
| May 18 | Demo polish: animated verdict reveal, Try Example cards, haptic feedback, app icon, code cleanup |

---

## 12. Links

- **Fine-tuned model**: [huggingface.co/rudrararaa/satya-gemma4-e4b-lora](https://huggingface.co/rudrararaa/satya-gemma4-e4b-lora)
- **APK**: See [RELEASE_NOTES.md](./RELEASE_NOTES.md)
- **Demo video**: *(placeholder — coming before deadline)*

---

## 13. Glossary

- **Verdict** — the structured output of an analysis: confidence score + evidence + recommendation
- **Federated verdict cache** — Firebase Firestore collection storing signed verdicts, keyed by content hash
- **Content hash** — SHA-256 of the analyzed content (video, image, audio); used as the lookup key
- **Device keypair** — Ed25519 keypair generated on first app launch, used to sign verdicts
- **Consensus** — when multiple independent devices produce matching verdicts for the same content hash, building trust without a central authority
- **E4B** — Gemma 4's "Effective 4B" parameter model, designed for on-device deployment
- **LoRA** — Low-Rank Adaptation, a parameter-efficient fine-tuning technique
- **Function calling** — Gemma 4's native ability to produce structured JSON output matching a schema

