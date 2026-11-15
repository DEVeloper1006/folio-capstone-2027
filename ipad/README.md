# Folio iPad

Integration guide for the native SwiftUI/PencilKit app currently developed in the separate `ink-pad` repository.

**Status:** this branch adds documentation only. The native app and recognition research have not been imported yet. The existing web app remains in `client/`.

## Proposed repository layout

```text
folio-capstone-2027/
├── client/                       # Existing TanStack Start / MathLive web app
├── ipad/
│   ├── README.md                 # This guide
│   └── app/                      # Planned: intact ink-pad source import
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
│   └── folio-ipad-labs/           # Planned: intact research source import
├── shared/
│   └── contracts/                # Future: notebook, recognition and command formats
└── .mac/                         # Existing source documents; preserve in place
```

The existing `aryaans-experimentation` branch also contains a `macos/` app and `outputs/` prototype. Review and integrate that work separately; do not replace `client/` or silently merge it during the iPad import.

The old labs browser/Mac workspace stays under `research/folio-ipad-labs/experiments/folio-workspace/` initially. It is a reference prototype, not a replacement for this repository's current `client/`. The labs `shared/` folder contains Python research helpers; it is separate from the proposed cross-platform `shared/contracts/`.

## Run the existing web app now

From the repository root, with Node.js and pnpm installed:

```bash
cd client
pnpm install
pnpm dev
```

Open http://localhost:3000. Node/pnpm versions are not pinned in this repository yet. See the root README and CONTRIBUTING guide for the existing checks and production commands. The current playground keeps edits in memory and resets them on refresh.

## Run the iPad app after importing its source

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

The app includes Pencil input, recognition review, LaTeX rendering and local computation. Symbolic computation does not require the Python/SymPy server or a Mac recognition endpoint. Native app details will live in `ipad/app/docs/` after import.

### Handwriting recognition assets

The validated Core ML models are generated local resources and are not ordinary Git source. Obtain the existing validated export artifacts, then run this command after source import:

```bash
python3 ipad/app/scripts/prepare-local-recognition.py \
  --artifacts /absolute/path/to/validated/on-device-texteller
```

The script verifies the recorded model/adapter and package hashes, then stages the encoder, decoder and tokenizer under `ipad/app/inkpad/inkpad/Resources/LocalTexTeller/`. It does not download or convert models. Rebuild the app afterward. A source checkout without these assets is not a ready-to-use local handwriting-recognition installation.

The script currently defaults to the old sibling-repository layout, so pass `--artifacts` explicitly after migration. Model conversion/training requirements remain with the research project.

## Branches and import sequence

- Keep `main` as the shared integration branch. Keep platform code in folders, rather than maintaining permanent iPad and PC branches.
- This local preparation branch is `chore/ipad-monorepo-setup`; it contains this guide and links from the root documentation.
- Import the checkpointed iPad source in a focused `chore/import-ipad` branch from the latest `main`. Preserve its existing history, for example with a non-squashed subtree import at `ipad/app/`. Keep the Xcode layout intact first.
- Import research source separately at `research/folio-ipad-labs/`, preserving its history and fixing explicit cross-repository paths. Do not introduce nested `.git` directories.
- Use short-lived branches such as `feat/ipad/recognition-review`, `feat/client/notebook-save` and `feat/shared/document-format`, then review through pull requests.
- Preserve the original repositories, signed working app and notebook backups until the relocated builds and model staging have been verified.

Before importing, checkpoint the latest local changes: many working iPad features currently exist as modified or untracked files and would be missed by importing only the old committed branch. Preserve existing test history; coordinate its import with the repository's current pause on new test development rather than discarding tests or adding new ones during this documentation change.

This repository is public. Keep personal handwriting/notebook data, database backups, `.reports/`, model weights, virtual environments, installed dependencies and generated builds outside committed source. Preserve each imported project's ignore rules and model provenance/license files.

A monorepo provides one place to develop the apps; it does not itself add notebook synchronization or a shared runtime. Define portable document/command contracts before extracting shared implementation code.
