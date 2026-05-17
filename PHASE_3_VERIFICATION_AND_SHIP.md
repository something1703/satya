# PHASE 3 — VERIFICATION & SHIP

> **Goal:** End this phase with the project submitted to Kaggle. That means: signed verdicts publishing to a federated cache, a polished 3-minute demo video on YouTube, a landing page live, a public APK available, fine-tuned weights published, and a complete Kaggle writeup filed.
>
> **Duration:** Days 7–9
> **Owner ratio:** Everyone, every hour
> **Exit checkpoint:** see Section 13 of this file

---

## 0. Agent Rules For This Phase

- Phase 2 checkpoint must be 13/13 green. Half-finished analysis pipelines do not survive Phase 3 polish — go back if needed.
- Phase 3 is where most hackathon teams collapse. The technology works; the storytelling, packaging, and submission filing don't get the attention they need. Discipline matters here more than coding.
- The video is the most important artifact you produce in this entire project. More important than the code. Treat it that way.
- Do not start writing the Kaggle writeup last. Draft it Day 7 — refining a draft is faster than starting from blank Day 9.
- Submission is filed by Day 9 noon UTC. Not midnight. Noon. Last-minute submissions hit Kaggle slowdowns and get lost.

---

## 1. What This Phase Produces

By the end of Phase 3, all of the following are live and public:

1. The federated verdict cache running on Firebase, accepting signed verdicts and returning matches
2. Every verdict produced by the app is signed with the device's Ed25519 key and published to the cache
3. Signature verification works — the app proves a cached verdict came from a real SATYA device, not a forged source
4. The 3-minute demo video is shot, edited, and published to YouTube as a public video
5. A landing page is live at a real domain (preferred) or vercel.app subdomain (acceptable)
6. The signed APK is published to GitHub Releases with a public download link
7. The Kaggle writeup is complete, under 1,500 words, and submitted
8. Hugging Face model card is finalized with full benchmark documentation
9. The submission is filed on Kaggle before May 18 noon UTC

---

## 2. The Three Final Tracks

Phase 3 has the same parallel structure as Phase 2 but the roles shift:

| Track | Primary owner | Supporting | What gets built |
|---|---|---|---|
| **D — Verification Infrastructure** | Crypto/Security + Full-stack | App Dev | Ed25519 signing, Firebase cache, verification UI |
| **E — Storytelling** | Whoever's strongest at video + writing | Everyone reviews | Demo video, writeup, landing page |
| **F — Polish & Release** | App Dev + ML | Everyone | APK signing, release artifacts, model card, HF cleanup |

Track D is technical, must be done early. Track E is creative, must be iterated. Track F is execution, must be precise.

---

## 3. Track D — Verification Infrastructure

### 3.1 — Why we sign verdicts

The federated cache works only if verdicts cannot be forged. Without signatures, anyone could write to Firestore and inject fake "verdicts" claiming political deepfakes are authentic. With signatures, every verdict in the cache is cryptographically tied to a real SATYA device that produced it.

The trust model:

- Each SATYA installation generates an Ed25519 keypair on first launch
- The private key never leaves the device
- The public key is published to Firestore in a `public_keys` collection, indexed by `device_id`
- Every verdict published to Firestore carries a signature over `(content_hash, verdict_json, timestamp, device_id)`
- Any client (app or website) can independently verify a verdict: fetch the public key, verify the signature, confirm the verdict was produced by a real SATYA device

This is the same model that secures package registries (Sigstore), TLS certificates, and modern git commit signing. No invention required — just disciplined implementation.

### 3.2 — Keypair generation and storage

On first launch, the app generates an Ed25519 keypair using the `cryptography` Dart package. The private key is stored in Android's encrypted shared preferences (which use the system keystore behind the scenes). The public key is stored alongside it for fast access.

The first-launch flow:

1. App checks if a keypair already exists in secure storage
2. If yes → load it
3. If no → generate fresh keypair, store both keys, generate a random `device_id` (UUID v4), publish public key to Firestore under `public_keys/{device_id}`
4. Cache the keypair in memory for the session

The agent puts all this in `mobile/lib/crypto/signing_service.dart`.

Anonymous Firebase Auth (enabled in Phase 1) is used so each device has a stable Firestore identity without requiring real user accounts. The `device_id` is paired with the anonymous auth UID.

### 3.3 — The verdict signing flow

When the analysis engine produces a verdict, the app:

1. Serializes the verdict JSON in a canonical form (keys sorted alphabetically, no whitespace) — canonical serialization is critical for signatures to verify
2. Constructs the signed payload: `{content_hash, verdict_canonical_json, timestamp_utc, device_id}`
3. Signs the payload with the device's private key
4. Wraps everything into the final document for Firestore:

```json
{
  "content_hash": "sha256:abc123...",
  "verdict": { ... full verdict object from Phase 2 schema ... },
  "signature": "ed25519:base64sig...",
  "device_id": "uuid",
  "signed_at": "2026-05-15T08:14:22Z",
  "schema_version": "v1",
  "app_version": "1.0.0",
  "model_version": "satya-gemma4-e4b-lora-v1"
}
```

5. Writes this document to `verdicts/{auto_id}` in Firestore

The agent codes this as `signAndPublish(Verdict v)` in `verdict_cache/verdict_cache_service.dart`. Returns the Firestore document ID for reference.

### 3.4 — The cache lookup flow

The lookup flow runs BEFORE local analysis to save inference cost on already-seen content:

1. Compute SHA-256 of the content the user wants to analyze
2. Query Firestore: `verdicts.where("content_hash", "==", hash).limit(20).get()`
3. If results exist:
   - Verify each signature against the corresponding public key (fetch from `public_keys` cache, cache locally)
   - Discard any verdicts whose signature fails verification
   - If 3+ valid verdicts exist with matching `overall_verdict`, display consensus immediately
   - If verdicts disagree, run local analysis anyway and present all viewpoints
4. If no results, proceed to local Gemma 4 analysis as normal

The "3+ valid verdicts → consensus" threshold is configurable in `app_config.dart`. Start at 3 for the demo.

### 3.5 — Firestore security rules

Phase 1 used TEST mode (open). Lock this down in Phase 3.

The rules to deploy in `backend/firestore.rules`:

- Anyone can READ `verdicts` and `public_keys` (this is the federated property — public verification matters)
- Authenticated users (anonymous auth counts) can CREATE in `verdicts` but the document must contain a valid `content_hash`, `verdict`, `signature`, `device_id`, and `signed_at`
- No one can UPDATE or DELETE existing verdicts (verdicts are immutable history)
- Authenticated users can CREATE in `public_keys` only with their own auth UID matching the `device_id`
- No one can modify another device's public key (impersonation protection)

Server-side validation of signatures is impractical in Firestore rules alone (no ed25519 in rules language). The signature verification happens client-side at read time. This is acceptable because:

- The cache is a hint, not a source of truth — every device independently verifies signatures it cares about
- Forged unsigned writes are detected and ignored by readers
- A Firebase Function (Section 3.6) periodically prunes invalid entries server-side

Deploy rules:

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. From the repo root: cd backend
  2. Run: firebase login (if not already logged in)
  3. Run: firebase use --add  → select your satya-verdict-cache project
  4. Run: firebase deploy --only firestore:rules
What you need to give me back:
  - Confirmation that deploy succeeded
  - Any error output from the command
Reason this is needed:
  TEST mode rules are public-write — we must lock down before the cache goes live.
```

### 3.6 — Firebase Cloud Function: server-side pruner

A lightweight Cloud Function runs every 6 hours and:

1. Reads recent `verdicts` documents
2. Fetches matching public keys from `public_keys` collection
3. Verifies signatures using `tweetnacl` or `@noble/ed25519` in Node.js
4. Deletes documents with invalid signatures
5. Logs pruning stats to a `_audit_log` collection

This is a defense-in-depth measure. The client-side verification at read time is the primary defense; this is the backstop.

Code goes in `backend/functions/signature_verify.ts`. Use `firebase-functions` v6+ with TypeScript.

Deploy:

```
cd backend
firebase deploy --only functions
```

### 3.7 — The verification UI in the app

The verdict screen (from Phase 2) gets new elements in Phase 3:

- **Verification badge** on each verdict card showing one of:
  - ✓ "Verified by N devices" (green) — when 3+ devices independently produced matching verdicts
  - ⚠ "Disputed — verdicts disagree" (amber) — when devices produced different verdicts
  - "Your device's analysis" (neutral) — when this is the first analysis of this content
- **"How is this verified?"** info link → opens a modal explaining the cryptographic verification briefly with a "Learn more" link to the landing page

The verification status is computed once when the verdict screen loads, not in real time.

### 3.8 — Privacy guarantees: explicit and visible

The app's settings screen has a "Privacy" section listing what does and does not leave the device:

- ❌ Your content is **never** uploaded
- ❌ Your phone's identity is **not** shared with us
- ✓ Only the analysis result (verdict) and the hash of the content (which cannot recover the original) are published
- ✓ All analysis happens on your phone

This isn't just marketing — it's auditable in the code. Note this in the writeup with a code reference.

---

## 4. Track E — Storytelling

### 4.1 — The video is the project

The hackathon scoring is 30 points on the video. The previous winner won partly on the strength of the video. Treat it as a deliverable equal in importance to the code.

Budget two full days for the video: Day 7 to shoot, Day 8 to edit. Do not compress this.

### 4.2 — The video script

The video is **3 minutes maximum**. Hard cap. Going over disqualifies. Aim for 2:45 to leave buffer.

Three acts:

**Act 1 — The problem (0:00–0:35)**

Open with real headlines. Not stock footage of "AI" — actual screenshots of real misinformation events: WhatsApp lynching news reports, election deepfakes from 2024, fake medical advice from COVID. No narration for the first 10 seconds — let the headlines speak.

Then a single voice (whoever has the most credible, warm voice in the team) narrates over a soft cut to a person scrolling their phone:

> *"In 2024, 900 million people were exposed to AI-generated political content. In India, a single WhatsApp forward can spread to ten million people in a day. The problem isn't that we can't detect manipulation — it's that detection lives in fact-checking newsrooms in English, and the forwards are already in your aunty's group chat."*

Cut to your demo subject — a young woman, your team member, looks worried at her phone. The setup is real: a video has just landed in her family group. Her uncle has already shared it.

**Act 2 — The product (0:35–1:50)**

She opens SATYA. The UI is calm, clean, deliberate. She shares the video into the app. The analyzing screen plays — show enough of it that judges feel the time pass (real time, no fake speed-up; if it takes 12 seconds, show 12 seconds with B-roll of the device).

The verdict appears: LIKELY SYNTHETIC, 91% confidence. The evidence list expands — facial inconsistency at 0:14, audio sync break at 0:18. The recommendation: DO NOT FORWARD.

Cut to her sharing the verdict card back to the group. Her uncle responds with a different emoji this time. The forward dies.

A montage follows — show two more analyses on different content types: an AI-generated image of a politician, a synthetic voice clip of a CEO. Each produces a clear verdict in seconds. Each runs offline (show the airplane mode toggle).

**Act 3 — Why this matters (1:50–2:45)**

Pull back. Cut to the architecture in motion — a visualization of multiple devices contributing to a shared verdict cache. One device analyzes a video, signs it. Three other devices encounter the same video, see the verdict instantly, verify the signature.

Narration:

> *"SATYA runs on a $200 phone. The model never sees a server. Every verdict carries a cryptographic signature anyone can verify. As more people use it, the network gets smarter — without ever centralizing the content or the trust."*

Close on the team member's face. A small smile. End card: SATYA, project URL, GitHub URL.

### 4.3 — Shot list

The agent generates this shot list in `video/shot_list.md` so the team knows exactly what to capture before shooting day:

| Shot | Description | Duration | Location | Equipment |
|---|---|---|---|---|
| 1 | Tight shot of phone with WhatsApp open, forward arriving | 4s | Indoor, soft natural light | Phone + tripod |
| 2 | Subject's worried face looking at screen | 3s | Same location | Camera with shallow DoF |
| 3 | Hand opens SATYA, taps share-from-WhatsApp | 6s | Same | Phone screen capture |
| 4 | App's analyzing screen with status updates | 10s | Phone screen capture | — |
| 5 | Verdict screen revealing with smooth animation | 6s | Phone screen capture | — |
| 6 | Evidence card expanding, user reading | 8s | Phone screen capture | — |
| 7 | Subject sharing verdict back to WhatsApp group | 5s | Same | — |
| 8 | Architecture animation (post-production) | 12s | Motion graphics | Built in After Effects or Figma → video |
| 9 | Montage: image analysis | 6s | Phone screen | — |
| 10 | Montage: audio analysis with waveform | 6s | Phone screen | — |
| 11 | Airplane mode toggle close-up | 3s | Phone close-up | — |
| 12 | Subject's small smile, closing shot | 4s | Same | — |
| 13 | End card with URLs | 5s | Motion graphics | — |

Total: 78 seconds of footage + narration over B-roll for the remaining 100 seconds.

### 4.4 — Audio and music

- Narration: recorded with a decent mic (a smartphone with a good mic against the cheek works fine if no studio mic is available; do not use built-in laptop mic)
- Background music: licensed-free track from Epidemic Sound, Artlist, or YouTube Audio Library — pick something contemplative, not corporate-pumping
- Sound design: include subtle UI sounds (the share intent ding, the verdict reveal chime) — these are GemmaVision-pattern accessibility cues that also make the video feel polished

### 4.5 — Editing standards

- 1080p or 4K — judges will probably watch at 1080p but having 4K available is professional
- Color graded consistently — even basic Lumetri/Color Wheels application beats raw footage
- Subtitles burned in (not just YouTube auto-captions) — judges may be in noisy environments
- End frame holds for at least 3 seconds with the URL clearly visible
- Export with the YouTube preset for best compression compatibility

### 4.6 — YouTube upload

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. Upload the final video to YouTube on a non-personal channel if possible (use a Google account dedicated to the project)
  2. Set visibility: PUBLIC (not unlisted — judges need to share the link)
  3. Title: "SATYA — On-Device Truth Detection with Gemma 4 | Gemma 4 Good Hackathon"
  4. Description: First paragraph is your elevator pitch. Then bullets for: GitHub URL, Landing page URL, APK download URL, Hugging Face model URL, team members. End with hashtags: #Gemma4 #Hackathon #AI #Privacy
  5. Enable: comments, likes
  6. Set: do NOT mark as "made for kids"
  7. Add to a public playlist if relevant
What you need to give me back:
  - The public YouTube URL
  - Confirmation that it plays in incognito mode without login
Reason this is needed:
  Hackathon requires a public YouTube video as the primary submission asset. Login walls disqualify the entry.
```

### 4.7 — The Kaggle writeup

Maximum 1,500 words. Treat this as a long-form blog post that proves the demo is real.

Structure (`kaggle_writeup.md`):

**Title:** SATYA — On-Device Truth Detection with Gemma 4
**Subtitle:** Privacy-first misinformation detection that runs in your pocket, verified by a federated network of cryptographically signed verdicts

**Section 1 — Cover image** (top of writeup, attached separately)

Use a clean composition showing the verdict UI from the app on a phone, with the SATYA logo. This is what judges see in the gallery view — make it count.

**Section 2 — The problem (~200 words)**

State the misinformation crisis with concrete numbers from real sources. Cite the 2018 WhatsApp lynching reports, the 2024 deepfake election content surge. End on: cloud AI cannot solve this because privacy, cost, latency, and centralization are all incompatible with the user.

**Section 3 — The approach (~300 words)**

Explain SATYA in 3 sentences first. Then expand:

- Gemma 4 E4B running locally via flutter_gemma + MediaPipe
- Fine-tuned with Unsloth on a 10,000-example misinformation dataset including Indian regional sources
- Multimodal: video frames + audio + text in one inference
- Verdicts signed with Ed25519, published to a federated cache anyone can verify
- 100% privacy: no content leaves the device, ever

Include the architecture diagram (export from your slides or draw a clean version).

**Section 4 — Gemma 4 usage in detail (~250 words)**

Show specifically how each Gemma 4 feature is used. Not generically — point to code paths.

| Feature | Where it's used | Why it matters |
|---|---|---|
| Native multimodal | `multimodal_pipeline.dart:48` — single inference over frames + audio + text | One model, one inference, coherent reasoning |
| Function calling | `gemma_service.dart:122` — submit_verdict tool definition | Schema-enforced structured output |
| Thinking mode | Available in dev builds | Auditable reasoning chain |
| Native audio input on E4B | Audio-only WAV passed directly | No separate STT pipeline |
| 128k context | Forwarded thread + cached reference data | Whole-message context |
| Apache 2.0 licensing | Allows publishing fine-tuned weights | Open ecosystem |

**Section 5 — Fine-tuning details (~250 words)**

- Base: Gemma 4 E4B
- Method: LoRA rank 16, alpha 32
- Training set: 10,247 examples from 7 sources, balanced across English/Hindi/Spanish content
- Hardware: Kaggle T4 x2, 8.5 hours wall-clock
- Result: +14.2% accuracy improvement over base on held-out test set, +0.21 F1 improvement on overall verdict prediction
- Calibration: ECE improved from 0.18 to 0.06 (well-calibrated confidence)

Include a table comparing base vs fine-tuned across categories. This is a key chart for the Unsloth prize.

Publish link: https://huggingface.co/<your-username>/satya-gemma4-e4b-lora

**Section 6 — The federated verdict cache (~200 words)**

Explain the trust model briefly. Make clear:
- Verdicts are signed with Ed25519 keys generated on-device
- Cache stores hashes, not content
- Anyone can verify signatures independently
- Consensus emerges from independent device agreement, not central authority

This section is what wins Safety & Trust track points.

**Section 7 — Challenges and what we learned (~150 words)**

Be honest. Real lessons judges trust:

- Fine-tuning on synthetic-only datasets failed initially; mixing in regional fact-check examples doubled the lift
- MediaPipe model conversion was finicky for new Gemma versions; documented our workaround in the repo
- Verdict consistency across team members was poor until we standardized 8 test files
- Inference latency on mid-range devices was 25s+ until we moved to isolates and reduced frame count

**Section 8 — What's next (~100 words)**

- WhatsApp Business API integration for fact-checking partnership
- Multi-language verdict generation (currently English, extending to 10 Indian languages and 8 other major languages)
- Federation across regional verdict caches for local context-aware consensus
- Browser extension and desktop app sharing the same federated cache

End on the vision: a world where every smartphone has a private, free, real-time misinformation defense built-in.

### 4.8 — The landing page

Live at `satya.app` if available (check DNS — buy from Namecheap, ~$12/year), else `satya.vercel.app` or similar.

Single-page Next.js site at `landing/`. Sections (top to bottom):

1. Hero — product name, tagline, hero shot of the phone running SATYA, "Download APK" + "View source" buttons
2. The problem — 3 stats, 3 sentences
3. How it works — animated diagram or 3 screenshots
4. Demo video embed (YouTube iframe)
5. Cryptographic verification explainer — the "anyone can verify" property
6. Open source — Apache 2.0 callout, GitHub link
7. Team — 5 photos, names, roles
8. Footer — links to Hugging Face, GitHub, Kaggle writeup

Deploy from `landing/` to Vercel:

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. From your Vercel account, click "Add New Project"
  2. Import the satya GitHub repo
  3. Root directory: landing/
  4. Framework preset: Next.js (auto-detected)
  5. Deploy
  6. (Optional) Custom domain: buy satya.app from Namecheap, point to Vercel
What you need to give me back:
  - The live URL of the landing page
Reason this is needed:
  Hackathon submission requires a live demo link. The landing page also acts as the public face of the project for the broader community.
```

---

## 5. Track F — Polish & Release

### 5.1 — The APK release

The app must be downloadable from a public URL with no sign-in. GitHub Releases is the simplest distribution.

Build a release APK:

```
cd mobile
flutter build apk --release --split-per-abi
```

Three APKs are produced (arm64, armeabi-v7a, x86_64). Upload all three to a GitHub release.

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. Generate an upload keystore for signing (one-time): keytool -genkey -v -keystore satya-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias satya
  2. Save the keystore password and key password in a secure place (NOT in the repo)
  3. Configure mobile/android/key.properties (gitignored already) with the keystore details
  4. Re-run flutter build apk --release after configuring signing
  5. Go to https://github.com/<org>/satya/releases
  6. Click "Draft a new release", tag name: v1.0.0
  7. Title: "SATYA v1.0.0 — Hackathon Submission Release"
  8. Description: brief release notes + system requirements + install instructions
  9. Attach the three APK files from build/app/outputs/flutter-apk/
  10. Publish the release (not draft)
What you need to give me back:
  - The public release URL
  - Confirmation that the APK downloads successfully in incognito
Reason this is needed:
  Hackathon submission needs a public APK download for judges to install. Unsigned debug APKs may fail to install on some devices.
```

Test the published APK on a fresh device that wasn't used for development. If install fails, the keystore or ABI split is wrong — debug before submitting.

### 5.2 — Final fine-tuned model card on Hugging Face

The Hugging Face model card needs to be production-grade. Use the template at https://huggingface.co/docs/hub/model-cards.

Required sections in the model card:

- Model description (what it does, base model, training method)
- Intended use and out-of-scope use
- Training data (sources with citations)
- Training procedure (hyperparameters table)
- Evaluation (benchmark table with base vs. fine-tuned comparison)
- Bias, risks, and limitations (honest section — every model has bias; transparency wins trust)
- How to use (code snippet for loading the LoRA adapter)
- Citation (BibTeX entry pointing to the Kaggle writeup)

Two artifacts on Hugging Face:

1. `<username>/satya-gemma4-e4b-lora` — the LoRA adapter (small, ~50MB)
2. `<username>/satya-gemma4-e4b-merged-mediapipe` — the merged + converted MediaPipe-format model used in the app (large, ~3-4GB)

### 5.3 — README of the GitHub repo

The repo's root README is what someone lands on. It needs to:

- Open with a punchy 2-sentence description
- Show a hero image or animated GIF of the app
- Have a "Try it" section with the APK link, landing page link, video link
- Have a "How it works" section with the architecture diagram
- Have a "Build from source" section with concrete steps (someone with a clean machine should be able to follow it)
- Link to the Kaggle writeup
- Credit the team
- License: Apache 2.0

Time spent on this README pays off — judges will read it.

### 5.4 — Removing development cruft

Before final submission:

- Remove the Phase 1 "Hello Gemma" test screen if not already done
- Remove the Phase 1 Firestore test button
- Remove or gate the dev-build analysis logs (Section 5.6 of Phase 2)
- Clean up commented-out code
- Remove any hardcoded test data
- Ensure no API keys or tokens are in the repo (run `git log -p | grep -i 'token\|key\|secret'` to audit)
- Format all Dart code with `dart format` and all Python with `black`

### 5.5 — One final integration test

Day 9 morning: a fresh team member who hasn't seen the build for 24 hours installs the published APK on a phone that's never had the app before. They try:

- Cold launch and model download
- Sharing a video from WhatsApp
- Receiving a verdict
- Sharing the verdict back
- Cache hit scenario (analyze the same video again — should be instant)
- Working offline (toggle airplane mode after model is downloaded)

Any failure here is a blocker. Fix it before submitting. Failing during judging is a worse outcome than submitting an hour later.

---

## 6. The Kaggle Submission Filing

This is the actual act of submitting. It's not optional, it's not automatic, and it's where teams sometimes fumble.

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. Go to https://www.kaggle.com/competitions/gemma-4-good-hackathon
  2. Click "Submit Writeup" (or the equivalent submission entry point)
  3. Title: SATYA — On-Device Truth Detection with Gemma 4
  4. Subtitle: Privacy-first misinformation detection that runs in your pocket
  5. Track: select the appropriate primary track (recommend "Safety & Trust" but check what the form offers)
  6. Paste the writeup content from kaggle_writeup.md (under 1,500 words)
  7. Cover image: upload the prepared cover from Section 4.7
  8. Attachments — link these as Project Links:
     - Video: YouTube URL from Section 4.6
     - Public Code Repository: GitHub URL
     - Live Demo: Landing page URL
     - Also include in the writeup body: APK download URL, Hugging Face URL
  9. Media Gallery: attach 4-6 screenshots of the app + the architecture diagram
  10. Before clicking Submit:
      - Confirm word count is ≤1500
      - Confirm all links work in incognito
      - Confirm video plays in incognito
      - Confirm APK downloads in incognito
  11. Click Submit
  12. After submission, you can un-submit, edit, and re-submit. Do this if you spot any issue before May 18, 23:59 UTC.
What you need to give me back:
  - Confirmation of submission
  - The submission URL on Kaggle (for our records)
Reason this is needed:
  Until "Submit" is clicked, the writeup is a draft and will not be judged. This is the most important step in the entire project.
```

---

## 7. Backup Plans

Every step in this phase has a way to fail. Plan accordingly.

**If video shoot fails on Day 7:**
- Day 8 morning becomes shoot day; edit by Day 9 morning
- Reduce shot list to essentials: phone-only screen recordings + voiceover, no in-person footage

**If MediaPipe model conversion fails:**
- Use base Gemma 4 in the app; ship the fine-tune as a Hugging Face artifact only
- Writeup is honest: "Due to MediaPipe conversion limitations for the LoRA adapter, the shipped APK uses base Gemma 4 E4B. The fine-tuned model is published on Hugging Face for researchers and is used in our benchmark numbers. We have documented the conversion issue and will publish a converted version when MediaPipe support is updated."
- Still wins Unsloth prize

**If Firebase has issues:**
- Cache becomes optional; the app works fine without it
- Writeup pitches the cache as the federation roadmap rather than the current state

**If APK signing fails:**
- Distribute unsigned debug APK with clear instructions about enabling "Install from unknown sources"
- Acceptable for hackathon judging though not ideal

**If a team member drops out in Phase 3:**
- Tracks E and F can be carried by 1 person each at minimum
- Track D needs at least 1 person until cache is live; can be paused after that

---

## 8. The Submission Window

The deadline is May 18, 2026, 23:59 UTC. Your real working deadline:

| Time (UTC) | Status |
|---|---|
| May 16, 23:59 | All code complete |
| May 17, 23:59 | Video uploaded, writeup drafted, all links working |
| May 18, 12:00 (noon) | Submission filed |
| May 18, 12:00–23:59 | Buffer for fixes and re-submissions |
| May 18, 23:59 | Hard deadline |

The 12-hour buffer is non-negotiable. Submissions filed in the last hour hit Kaggle slowdowns and sometimes don't register.

---

## 9. After Submission

Once submitted, the team's work isn't quite done.

- Post on Twitter/X with the YouTube link tagging @kaggle and @googleai
- Post in the Kaggle competition discussion forum introducing your project
- Post on Reddit r/MachineLearning, r/LocalLLaMA, r/Flutter (in that order of priority)
- Post on LinkedIn — team members share with their networks
- Reach out to AI/ML journalists with a press-style note about the project

Engagement matters. Judges check whether projects have community traction. A project with 10k YouTube views suggests broader appeal than one with 30.

---

## 10. Post-Hackathon Continuity

Whether SATYA wins or not, it should keep running:

- Keep Firebase free tier active — the verdict cache is live infrastructure
- Respond to GitHub issues
- Plan a Hacker News launch for a week after the hackathon ends (post-result announcement)
- If we win, the prize money funds an iOS port and the multi-language expansion mentioned in the writeup

Add `docs/POST_HACKATHON_ROADMAP.md` with this content as a public commitment.

---

## 11. Mid-Phase Reality Check

End of Day 7, pause:

- Is the verdict cache actually working end-to-end (sign → publish → fetch → verify)? If not, all of Day 8 goes to this; the demo collapses without it.
- Does the video script actually feel emotional when read aloud? If it feels corporate or generic, rewrite — this is the highest-leverage 30 minutes you can spend.
- Have all 5 team members watched a rough cut of the video? Each person should flag the weakest 10 seconds — that's where to cut.
- Is the writeup at 1,500 words and feeling tight, or 3,000 words and bloated? Cut early. Writeups under 1,200 words often outperform — judges have many to read.

If any of these are red, drop the next scheduled task and fix this first.

---

## 12. The Last 24 Hours

Day 9 is not a coding day. It is a polish, test, ship day.

- Morning (UTC): final integration test with fresh device; fix anything broken
- Mid-morning: final video edit pass with team review; export final master
- Late morning: writeup final review; trim to 1,500 if needed
- Noon: file the Kaggle submission
- Afternoon: write social media posts, file r/MachineLearning post, draft Hacker News submission
- Evening: if any submission issue surfaces, fix and re-submit; otherwise rest

No new features after May 18 00:00 UTC. None. Anything new added in the last 24 hours is a stability risk.

---

## 13. Phase 3 Exit Checkpoint

Run every item. All must pass before submission.

| # | Check | How to verify |
|---|---|---|
| 1 | Ed25519 keypair generation works on first launch | Fresh install, check Firestore for new public key entry |
| 2 | Verdicts published to Firestore carry valid signatures | Inspect a Firestore doc, verify signature with `openssl` or Python |
| 3 | Cache lookup returns cached verdicts when content hash matches | Submit same content twice, second submission shows cached badge |
| 4 | Invalid signatures are rejected by the app on read | Manually inject a forged document, verify app ignores it |
| 5 | Firestore security rules deployed | `firebase deploy --only firestore:rules` succeeded |
| 6 | Cloud Function for server-side pruning deployed | `firebase functions:list` shows the function |
| 7 | Verification badge displays on verdict screen | Visual check on a real cached verdict |
| 8 | Demo video uploaded to YouTube, public, under 3:00 | Watch in incognito, verify duration |
| 9 | Landing page live and functional | Open in incognito, all links work |
| 10 | Signed release APK published on GitHub Releases | Download in incognito, install on test device, app launches |
| 11 | Hugging Face model card complete with benchmarks | Visit page, verify all sections present |
| 12 | Kaggle writeup ≤1500 words | Word count tool |
| 13 | Kaggle submission filed (not draft) | "Submitted" status confirmed |
| 14 | All links in writeup tested in incognito | Manual check |
| 15 | No secrets/tokens in repo | `git log -p | grep -iE 'token\|secret\|api_key'` returns nothing |
| 16 | All Phase 1 and Phase 2 test cruft removed from production app | Manual code review |
| 17 | Build log complete with daily entries | `docs/BUILD_LOG.md` covers all 9 days |
| 18 | Final tag pushed | `git tag submission-final && git push --tags` |

When all 18 pass: the team is done.

---

## 14. Closing Note

A hackathon submission is a snapshot. Whatever ships on Day 9 is what gets judged. The version you imagined on Day 1 is not the version you submit — that's normal and not a failure. What matters is that the version you submit:

- Solves a real problem
- Demonstrably works
- Tells a story a human cares about
- Uses the technology in a way that's genuinely Gemma 4-native, not generic

If all four are true, the work is good. The outcome — winning, finalist, none of the above — is not entirely in your control. Submitting a tight project you believe in is.

The team should have a moment together after submitting. Mark it. You built something real in nine days.
