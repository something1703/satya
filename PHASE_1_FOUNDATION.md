# PHASE 1 — FOUNDATION

> **Goal:** End this phase with a Flutter app running on a real Android phone that successfully calls Gemma 4 E4B locally and gets a response back. Everything else is built on this foundation.
>
> **Duration:** Days 1–2
> **Owner ratio:** App developer + ML person lead; everyone else supports
> **Exit checkpoint:** see Section 9 of this file

---

## 0. Agent Rules For This Phase

- Do not write any analysis logic yet. This phase is plumbing.
- Do not skip the verification commands. Every checkpoint exists because something silently breaks if it's skipped.
- When you hit a human-action block, **stop and wait**. Do not guess credentials or fabricate API keys.
- Commit to git at the end of every numbered section, not at the end of the phase.

---

## 1. What This Phase Produces

By the end of Phase 1, the following must be true:

1. A GitHub repository exists, public, called `satya`, owned by the team
2. A Flutter project lives inside `mobile/` and builds successfully on Android
3. A real Android device (or high-end emulator) can install the app
4. The app, when opened, downloads Gemma 4 E4B from Hugging Face on first launch and stores it locally
5. The app has a single text input where the user types a prompt and gets a Gemma 4 response back, fully on-device, no internet after the model is downloaded
6. A Firebase project exists and the app can read/write a test document to Firestore
7. A Kaggle notebook is set up with GPU access and Gemma 4 weights are loaded into it

Nothing else. No fancy UI. No analysis. No verdicts. No signatures. Just: the plumbing is real.

---

## 2. Accounts and Services To Create

This is the first thing the agent does. Each one is a human action block.

### 2.1 — GitHub Repository

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. Go to https://github.com/new
  2. Create a new repository named "satya"
  3. Make it PUBLIC (required by hackathon rules)
  4. Initialize with: README (uncheck), .gitignore (uncheck), license (Apache 2.0)
  5. Add team members as collaborators in Settings → Collaborators
What you need to give me back:
  - The repository URL
  - Your team members' GitHub usernames (so I can add them)
Reason this is needed:
  Hackathon requires public code repository as a deliverable.
```

After the user confirms, the agent clones the repo locally and copies the `docs/` folder (with the 3 phase files and README) into the root.

### 2.2 — Hugging Face Account and License Acceptance

Gemma weights are gated on Hugging Face. Each team member doesn't need their own account, but one designated person must accept the license.

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. Go to https://huggingface.co/join (or sign in if you have an account)
  2. Once logged in, go to https://huggingface.co/google/gemma-4-e4b-it
     (if Gemma 4 isn't published yet by hackathon start, use the latest available Gemma 4 variant — check https://huggingface.co/google for the exact model name)
  3. Click "Agree and access repository" and accept the license terms
  4. Go to https://huggingface.co/settings/tokens
  5. Create a new token: name "satya-dev", type "Read"
  6. Copy the token (starts with "hf_")
What you need to give me back:
  - The Hugging Face token (paste it; we will store it in .env, never commit it)
  - Confirmation that you accepted the Gemma 4 license
Reason this is needed:
  Required to download Gemma 4 weights both in the Kaggle notebook and in the app's first-launch model download flow.
```

Store the token in a file `.env.local` at the repo root. Add `.env.local` to `.gitignore` immediately.

### 2.3 — Firebase Project

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. Go to https://console.firebase.google.com/
  2. Click "Add project"
  3. Name it "satya-verdict-cache"
  4. Disable Google Analytics (not needed)
  5. Once created, click "Web" icon to add a web app — name it "satya-web"
  6. Copy the firebaseConfig object that appears
  7. In the left sidebar: Build → Firestore Database → Create database → Start in TEST mode → choose nearest region
  8. In the left sidebar: Build → Authentication → Get started → enable "Anonymous"
What you need to give me back:
  - The firebaseConfig object (apiKey, authDomain, projectId, etc.)
  - Confirmation that Firestore is created and Anonymous Auth is enabled
Reason this is needed:
  We need a backend store for the federated verdict cache. Firebase free tier handles our scale.
```

The agent stores the firebaseConfig in `mobile/lib/config/firebase_config.dart`.

### 2.4 — Kaggle Account With GPU Access

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. Go to https://www.kaggle.com/ and sign in (or sign up)
  2. Go to https://www.kaggle.com/settings — under "Phone Verification", verify your phone number
     (this is REQUIRED to unlock free GPU access — skip this and the fine-tuning will fail)
  3. Create a new notebook: https://www.kaggle.com/code → New Notebook
  4. In the notebook settings (right sidebar): Accelerator → GPU T4 x2
  5. Internet → On
  6. Save the notebook as "satya-finetune"
What you need to give me back:
  - The Kaggle notebook URL
  - Confirmation that phone verification is done (so GPU is unlocked)
Reason this is needed:
  Phase 2 fine-tuning runs in this notebook. Setting it up now avoids losing time later.
```

### 2.5 — Vercel Account (for landing page, lighter touch)

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. Go to https://vercel.com/signup
  2. Sign in with GitHub (uses your existing GitHub identity)
What you need to give me back:
  - Confirmation that the account exists
Reason this is needed:
  We'll deploy the landing page here in Phase 3. Account creation takes 30 seconds, so do it now.
```

---

## 3. Local Development Environment

The app developer's machine needs the following installed. The agent runs verification commands; if any fail, it tells the user exactly what to install.

### 3.1 — Required tools

| Tool | Minimum version | Verify command |
|---|---|---|
| Flutter SDK | 3.24.0+ | `flutter --version` |
| Android Studio | 2024.1+ | check via Tools menu |
| Android SDK | API 33+ | `flutter doctor --android-licenses` |
| Java JDK | 17 | `java -version` |
| Git | 2.40+ | `git --version` |
| Node.js | 20+ | `node --version` (for Firebase Functions later) |
| Python | 3.10+ | `python --version` (for local fine-tuning scripts) |
| Firebase CLI | latest | `firebase --version` |

The agent runs `flutter doctor` first. If anything reports errors, output:

```
🧑 HUMAN ACTION REQUIRED
flutter doctor reports the following issues: [paste output]
Please install/fix these and tell me when done.
```

### 3.2 — Android device setup

For real on-device testing (required, do not skip):

- Enable Developer Options on the test phone (tap Build Number 7 times in Settings)
- Enable USB Debugging
- Connect via USB
- Run `flutter devices` — the phone should appear in the list

Minimum device specs for Gemma 4 E4B:
- Android 12+
- 6GB+ RAM (8GB recommended for smooth inference)
- At least 6GB free storage (for model file)
- GPU: Adreno 640+ / Mali-G77+ / equivalent (most phones from 2021+)

If no team member has a suitable Android device, the fallback is Android Studio emulator with GPU acceleration enabled. Note: emulator inference is 3–5x slower than real device and battery/thermal behavior won't be representative. Document this limitation in the build log if used.

---

## 4. Flutter Project Initialization

### 4.1 — Create the project

Inside the cloned repo:

```
cd satya
flutter create --org com.satya --platforms=android,ios --project-name=satya mobile
cd mobile
```

The `--org com.satya` flag sets the bundle identifier. This matters later for Play Store and Firebase.

### 4.2 — Configure `pubspec.yaml`

Replace the dependencies block with these exact packages. Versions are anchored because mismatches between `flutter_gemma`, MediaPipe, and Firebase have caused build failures historically.

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Core
  cupertino_icons: ^1.0.6

  # Gemma 4 inference
  flutter_gemma: ^0.10.1
  path_provider: ^2.1.4
  path: ^1.9.0

  # Model download
  flutter_downloader: ^1.11.7
  permission_handler: ^11.3.1

  # Firebase
  firebase_core: ^3.6.0
  cloud_firestore: ^5.4.4
  firebase_auth: ^5.3.1

  # Crypto (for Phase 3)
  cryptography: ^2.7.0
  crypto: ^3.0.5

  # Media handling (for Phase 2)
  ffmpeg_kit_flutter: ^6.0.3
  image_picker: ^1.1.2
  share_plus: ^10.0.2
  receive_sharing_intent: ^1.8.0

  # UI utilities
  google_fonts: ^6.2.1
  flutter_svg: ^2.0.10+1
```

Run `flutter pub get` after this change. If it fails, capture the error and report — do not "fix" by removing packages.

### 4.3 — Android-specific configuration

In `mobile/android/app/build.gradle`:

- Set `minSdkVersion` to `26`
- Set `targetSdkVersion` to `34`
- Set `compileSdkVersion` to `34`
- Add the `multiDexEnabled true` flag inside `defaultConfig`

In `mobile/android/app/src/main/AndroidManifest.xml`, add the following permissions inside the `<manifest>` tag, before the `<application>` tag:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

Inside `<application>`, add an intent filter for receiving shared content (needed for Phase 2's "share to SATYA from WhatsApp"):

```xml
<intent-filter>
  <action android:name="android.intent.action.SEND" />
  <action android:name="android.intent.action.SEND_MULTIPLE" />
  <category android:name="android.intent.category.DEFAULT" />
  <data android:mimeType="*/*" />
</intent-filter>
```

### 4.4 — Verify the project builds

Run from the `mobile/` directory:

```
flutter build apk --debug
flutter run -d <device-id>
```

The default counter app should appear on the device. If not, stop and debug. Do not proceed.

### 4.5 — Commit and push

```
git add .
git commit -m "Phase 1: initialize Flutter project with dependencies"
git push origin main
```

---

## 5. The Folder Structure For The App

Inside `mobile/lib/`, create the following empty directories with a `.gitkeep` file in each (the actual code lives in Phase 2):

```
mobile/lib/
├── main.dart                  # entry point (modify in next section)
├── config/
│   ├── firebase_config.dart
│   └── app_config.dart        # constants, model URLs, schema versions
├── analysis/                  # Gemma 4 inference
│   ├── gemma_service.dart
│   ├── multimodal_pipeline.dart
│   └── verdict_schema.dart
├── crypto/                    # Ed25519 signing (Phase 3)
│   └── signing_service.dart
├── ui/
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── analyzing_screen.dart
│   │   └── verdict_screen.dart
│   └── widgets/
│       └── verdict_card.dart
├── verdict_cache/             # Firebase client
│   └── verdict_cache_service.dart
└── utils/
    ├── hash_utils.dart
    └── media_utils.dart
```

This structure is locked. Do not rename or reorganize without team agreement.

---

## 6. Bringing Gemma 4 To The Device

This is the heart of Phase 1. The agent's mental model: getting Gemma 4 to respond to "hello" on a real phone is harder than it looks. Do this in three sub-steps.

### 6.1 — Model file strategy

Gemma 4 E4B is roughly 3–4 GB. We cannot bundle it in the APK. Strategy follows the GemmaVision winner's approach:

- First app launch: detect model is missing, show download screen
- Download from Hugging Face using the user's token (one-time, prompted via the AI Edge Gallery-style flow)
- Store in app's private documents directory: `getApplicationDocumentsDirectory()`
- Subsequent launches: detect model exists, skip download, initialize directly

The `flutter_gemma` package supports this pattern natively. Reference its documentation at https://pub.dev/packages/flutter_gemma but anchor to the specific version pinned above — newer versions may have breaking API changes.

### 6.2 — Initialization flow

The app's startup logic, in plain English:

1. App opens
2. Check if model file exists at the expected path
3. If no → navigate to "Setup" screen with download progress
4. If yes → initialize `flutter_gemma` with:
   - Model path
   - Backend: `Backend.gpu` (fallback to CPU if GPU init fails — log this)
   - Max tokens: 1024 for Phase 1 (raise to 4096 in Phase 2)
   - Temperature: 0.3 (low for factual verdicts)
   - Streaming: enabled (UX requirement)
5. Navigate to "Hello Gemma" test screen

The agent writes this initialization service in `analysis/gemma_service.dart`. Keep it minimal in Phase 1 — single `init()` method, single `generateText(prompt)` method, that's it. Multimodal comes in Phase 2.

### 6.3 — Hello Gemma test screen

The Phase 1 success screen is intentionally crude. It has:

- A text field for the user to type a prompt
- A "Send" button
- A response area that streams Gemma 4's output as tokens arrive

That's it. No styling. No icons. It exists to prove the model works.

**Why streaming matters even in Phase 1:** if streaming works in Phase 1, it'll work for the verdict generation in Phase 2. If it doesn't, you need to know now, not later.

---

## 7. Firebase Wiring

Parallel track — while the app dev does Gemma 4, the full-stack person sets up Firebase.

### 7.1 — Connect Flutter to Firebase

From the `mobile/` directory:

```
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
flutterfire configure --project=<your-project-id>
```

This generates `mobile/lib/firebase_options.dart` automatically. Do not edit this file by hand — regenerate it if you change Firebase config.

### 7.2 — Initialize Firebase in `main.dart`

The agent modifies `main.dart` to call `Firebase.initializeApp()` before `runApp()`. Reference: https://firebase.google.com/docs/flutter/setup

### 7.3 — Test Firestore connectivity

Add a "Test Firestore" button on the Hello Gemma screen (delete after Phase 1). When tapped, write a document to a collection called `_phase1_test` with `{timestamp: now, device_id: <random>}` and read it back. Display result on screen.

If this works → Firebase is wired. If it doesn't → check the security rules in the Firebase Console (should be permissive during dev).

### 7.4 — Initial Firestore schema sketch

The agent creates these collections with TEST mode permissions (locked down properly in Phase 3):

| Collection | Purpose | Example doc |
|---|---|---|
| `verdicts` | Signed verdicts keyed by `content_hash` | `{ content_hash, verdict_json, signature, public_key, timestamp }` |
| `public_keys` | Device public keys for signature verification | `{ device_id, public_key_pem, first_seen }` |
| `_phase1_test` | Temporary test data, delete after Phase 1 | `{ timestamp, device_id }` |

---

## 8. Kaggle Notebook Setup (parallel track for ML person)

The ML person works in parallel to the app dev. By end of Phase 1, the Kaggle notebook must successfully load Gemma 4 weights and run a test inference. No fine-tuning yet — that's Phase 2.

### 8.1 — Notebook structure

Top cell — install Unsloth and dependencies:

```
!pip install unsloth
!pip install --upgrade transformers accelerate bitsandbytes
```

Second cell — log in to Hugging Face with the team token:

```
from huggingface_hub import login
login(token="<HF_TOKEN_FROM_SECTION_2.2>")
```

Use Kaggle's "Secrets" feature to store the token, not hardcoded in the notebook.

```
🧑 HUMAN ACTION REQUIRED
What you need to do:
  1. In your Kaggle notebook, click the lock icon in the right sidebar
  2. Click "Add a new secret"
  3. Label: HF_TOKEN
  4. Value: <paste the Hugging Face token from Section 2.2>
  5. Save
What you need to give me back:
  - Confirmation that the secret is saved
Reason this is needed:
  Hardcoding tokens in notebooks gets them committed to public outputs and is a security risk.
```

Third cell — load Gemma 4 via Unsloth:

```
from unsloth import FastModel
model, tokenizer = FastModel.from_pretrained(
    model_name="google/gemma-4-e4b-it",
    max_seq_length=4096,
    load_in_4bit=True,
)
```

(Use the exact model name confirmed in Section 2.2.)

Fourth cell — test inference:

```
inputs = tokenizer("What is misinformation?", return_tensors="pt").to("cuda")
outputs = model.generate(**inputs, max_new_tokens=128)
print(tokenizer.decode(outputs[0]))
```

If this prints a coherent response → checkpoint passed. If it errors → debug GPU allocation, model name, token authentication. Report the exact error.

### 8.2 — Commit notebook to repo

Export the notebook to `.ipynb`, save into `ml/unsloth_finetune.ipynb`, commit and push.

---

## 9. Phase 1 Exit Checkpoint

Run every item. All must pass before Phase 2 starts. If any fails, stop and fix.

| # | Check | How to verify |
|---|---|---|
| 1 | Public GitHub repo exists, team has access | Visit URL in incognito window |
| 2 | Repo contains `/docs`, `/mobile`, `/ml`, `/backend` folders | `ls satya/` |
| 3 | `flutter doctor` reports no errors | Run command |
| 4 | App builds for Android | `flutter build apk --debug` succeeds |
| 5 | App installs on physical phone | `flutter run` deploys and launches |
| 6 | Gemma 4 model downloads on first launch | Open app on fresh install, watch download complete |
| 7 | Gemma 4 generates a response to "hello" | Type "hello" → response streams back, in under 10 seconds |
| 8 | Firebase test write/read succeeds | Tap test button, see "OK" |
| 9 | Kaggle notebook runs inference | Cell 4 prints coherent text |
| 10 | All work committed and pushed | `git status` shows clean tree |
| 11 | Build log updated in `docs/BUILD_LOG.md` | File contains today's entries |

When all 11 pass: commit a tag `phase-1-complete` and proceed to `PHASE_2_CORE_ENGINE.md`.

```
git tag phase-1-complete
git push origin phase-1-complete
```

---

## 10. What Could Go Wrong In Phase 1 (And What To Do)

| Symptom | Likely cause | Fix |
|---|---|---|
| `flutter_gemma` build fails on Android | NDK version mismatch | Set NDK version in `android/app/build.gradle` to match what flutter_gemma docs specify |
| Model download stalls at 0% | Permission not granted | Check storage permissions on phone, ensure `permission_handler` requests are made before download starts |
| Model download fails with 401 | HF token wrong or license not accepted | Re-verify Section 2.2 steps |
| Gemma response is gibberish | Wrong model variant downloaded | Confirm using `-it` (instruction-tuned) variant, not base |
| Inference takes 60+ seconds | GPU backend not initialized | Check `Backend.gpu` is set, fall back to CPU only if necessary, log the choice |
| Firestore writes fail with permission denied | Rules in production mode | Confirm rules are in TEST mode for now |
| Kaggle notebook OOMs | Wrong model size selected | Use 4-bit quantization, confirm `load_in_4bit=True` |

---

## 11. Build Log Entry Template

The agent updates `docs/BUILD_LOG.md` at the end of every working session. Use this template:

```markdown
## Session YYYY-MM-DD #N
**Phase:** 1
**Hours:** X
**Team members active:** [names]

### Completed
- [bullet list]

### Blockers
- [bullet list with what's needed to unblock]

### Next session goal
- [single clear objective]

### Notes
- [anything else worth recording]
```

---

## Next Step

When all 11 checkpoint items pass: open `PHASE_2_CORE_ENGINE.md`.
