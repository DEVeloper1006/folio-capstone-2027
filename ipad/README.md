# Folio iPad

Run and structure guide for the native SwiftUI/PencilKit app imported from `ink-pad`.

**Status:** native source is in `ipad/app/`, and research source is in `research/folio-ipad-labs/`. The existing web app remains in `client/`. The apps do not yet share notebook persistence or synchronization.

## Repository layout

```text
folio-capstone-2027/
├── client/                       # Existing TanStack Start / MathLive web app
├── ipad/
│   ├── README.md                 # This guide
│   └── app/                      # ink-pad source import with history
│       ├── inkpad/
│       │   ├── inkpad.xcodeproj
│       │   ├── inkpad/            # SwiftUI, PencilKit, local math and recognition
│       │   ├── inkpadTests/
│       │   └── inkpadUITests/
│       ├── scripts/              # Model staging and math verification tools
│       ├── docs/                 # App architecture, operation syntax and limits
│       ├── design/
│       └── schemas/
├── research/
│   └── folio-ipad-labs/           # Research source import with history
├── shared/
│   └── contracts/                # Future: notebook, recognition and command formats
└── .mac/                         # Existing source documents; preserve in place
```

The existing `aryaans-experimentation` branch also contains a `macos/` app and `outputs/` prototype. Review and integrate that work separately; do not replace `client/` or silently merge it during the iPad import.

The old labs browser/Mac workspace stays under `research/folio-ipad-labs/experiments/folio-workspace/` initially. It is a reference prototype, not a replacement for this repository's current `client/`. The labs `shared/` folder contains Python research helpers; it is separate from the proposed cross-platform `shared/contracts/`.

## Run the web app

From the repository root, with Node.js and pnpm installed:

```bash
cd client
pnpm install
pnpm dev
```

Open http://localhost:3000. Node/pnpm versions are not pinned in this repository yet. See the root README and CONTRIBUTING guide for the existing checks and production commands. The current playground keeps edits in memory and resets them on refresh.

## Run the iPad app

Use a Mac with Xcode and the iOS 26.2 SDK or newer; the current app deployment target is iOS 26.2.

From the repository root:

```bash
open ipad/app/inkpad/inkpad.xcodeproj
```

Select the `inkpad` scheme, choose an iOS 26.2+ iPad simulator or connected iPad, then Run. For a physical iPad, select your development team under Signing & Capabilities and enable Developer Mode on the device.

A simulator compile can also be started from the repository root:

```bash
xcodebuild -project ipad/app/inkpad/inkpad.xcodeproj \
  -scheme inkpad -destination 'generic/platform=iOS Simulator' build
```

The app includes Pencil input, recognition review, LaTeX rendering and local computation. Symbolic computation does not require the Python/SymPy server or a Mac recognition endpoint. Native app details live in `ipad/app/docs/`.

The current math-context increment adds explicit, page-local grouping of recognized rows and bounded substitution from earlier accepted definitions into a selected equation. See [problem grouping and contextual computation](app/docs/problem-context-compute.md), the [iPad interaction checklist](app/docs/problem-context-ipad-checklist.md), the [growing major-version regression checklist](app/docs/problem-context-regression.md), and the [build checkpoints and rollback record](app/docs/problem-context-checkpoints.md). Contextual solving currently supports single-symbol definitions and at most one unresolved variable in linear or quadratic equations; general MathJSON, function definitions and systems remain unsupported.

### Handwriting recognition assets

The validated Core ML models are generated local resources and are not ordinary Git source. Obtain the existing validated export artifacts, then run:

```bash
python3 ipad/app/scripts/prepare-local-recognition.py \
  --artifacts /absolute/path/to/validated/on-device-texteller
```

The script verifies the recorded model/adapter and package hashes, then stages the encoder, decoder and tokenizer under `ipad/app/inkpad/inkpad/Resources/LocalTexTeller/`. It does not download or convert models. Rebuild the app afterward. A source checkout without these assets is not a ready-to-use local handwriting-recognition installation.

The script defaults to `research/folio-ipad-labs/results/on-device-texteller/` in this layout and retains the old sibling layout as a fallback. Pass `--artifacts` when exports live elsewhere. Model conversion/training requirements remain with the research project. The standalone research probe also locates `ipad/app/` automatically; `prepare_app.py --ipad-source` overrides it.

## Branches and import sequence

The migration has ordered checkpoints: `chore/ipad-monorepo-setup` for documentation, `chore/import-ipad` for the native source, `chore/import-research` for the experiments, then `chore/folio-monorepo-integration` for path fixes and verification. Source imports are non-squashed subtrees, preserving source ancestry and a commit of the current working files. Publish the final integration branch for review only after its relocated builds pass. Keep `main` and `aryaans-experimentation` unchanged.

After integration, use short-lived branches such as `feat/ipad/recognition-review`, `feat/client/notebook-save` and `feat/shared/document-format`. Platform folders provide organization without permanent platform branches. Review the separate Mac experiment independently.

Original repositories and their working files remain untouched. Local Git bundles and file inventories are stored outside this repository, in the original labs `.reports/monorepo-migration/` directory. Keep them, signed app backups and notebook backups until the migration is accepted. Roll back before merge by closing the PR and returning to `main`; if already merged, revert the PR merge through a separate reviewed change. Do not reset shared history.

## Source and asset boundaries

This repository is public. Keep personal handwriting/notebooks, database backups, `.reports/`, large model exports, virtual environments, installed dependencies and generated builds outside committed source. The existing research history deliberately contains the small Grade 12 LoRA adapter (3,061,656 bytes); its provenance files remain beside it. Older iPad history contains previously committed build-cache files, but the imported current tree excludes them. Source history is preserved without rewriting those old commits.

Imported documentation describes earlier checkpoints and may use the original sibling paths or historical capability counts. Use this guide for current top-level paths and each app's current source for behavior. Research and baseline tests are imported unchanged; no tests are added or extended by this migration.

A monorepo provides one place to develop the apps; it does not itself add notebook synchronization or a shared runtime. Define portable document/command contracts before extracting shared implementation code. `shared/contracts/` is a future location, not an implemented package.

## Migration verification

Verified before opening the migration PR with Xcode 26.2 (17C52):

- Debug builds passed for generic iOS Simulator and generic iOS device targets, with code signing disabled. The existing validated fp16 exports were staged locally and compiled; both compiled models, the tokenizer and manifest are present in the built app.
- The existing `client/` production build and TypeScript check passed using Node 25.6.1 and pnpm 10.32.1 with the frozen lockfile. The lockfile and client source are unchanged.
- All 173 native and 166 research checkpoint files were compared by SHA-256. Only the two documented cross-project path scripts differ. Both original source HEADs remain ancestors of the integration branch. `client/`, `.mac/`, `editor-comparison/` and repository rules remain unchanged.
- No nested Git repositories or submodules were introduced. Generated model assets remain ignored. Source and reachable-history scans found no matches for the credential patterns checked; this is not a comprehensive security audit.
- Updated Markdown passed the repository's local formatter and the migration edits passed `git diff --check`.

Build warnings remain: an existing canvas smoke helper uses deprecated `coordinateSpace`; Xcode skips optional App Intents metadata; the web build reports chunk-size/module-directive warnings. Neither build failed. This migration did not run new model inference, install on a physical iPad, validate Pencil gestures again, or execute every research prototype. Prior device validation remains evidence for the original app checkpoint, not a new device test of the relocated checkout.
