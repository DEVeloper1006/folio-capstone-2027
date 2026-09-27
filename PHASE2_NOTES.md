# Phase 2 Implementation Plan

## Build Order

### 0. Architecture Foundation
- New SwiftData models: ChatThread, Message, Snapshot, Insight, ClassSpace, WorkedExample
- New service protocols + mocks: ChatService, LearnerModelService, ReplayService, ClassService, VisualizationService
- Shared MathRenderer component (single WKWebView pool with SVG cache)
- Register all new models in inkpadApp schema
- **Build & verify**

### 1. Group A — AI Chat, LaTeX-native
- Rewrite ChatPanelView with MathRenderer for inline/display LaTeX
- Live LaTeX preview strip above input
- Ink chip (mock recognition → editable LaTeX)
- Scoped threads (step-anchored + page thread)
- Socratic dial (Hint/Nudge/Explain/Solve with session mode gating)
- Predict-then-reveal card
- Chat bubble markers in step gutter
- **Build & commit: "phase2: group-a chat"**

### 2. Group B — Math-aware Canvas
- Visualize cards (graph via Swift Charts, 2D vector, matrix heatmap) — draggable, leader line
- Live variable slider on ghost typeset taps
- Equivalence badge (≡/≠ chip from Relate action)
- Contradiction trace (× badge → highlight ancestor, dim unrelated)
- Unit/dimension check (Tier B preview)
- **Build & commit: "phase2: group-b canvas"**

### 3. Group C — Learning Layer
- Insights drawer with misconception cards linked to steps
- Formula sheet (LaTeX list, exportable)
- Fork to practise (Tier B preview)
- Confidence tap on gutter badges (1–3, mismatch outline)
- **Build & commit: "phase2: group-c learning"**

### 4. Group D — Replay & History
- Replay timeline scrubber (play/pause, speed control)
- Stroke-by-stroke animation using PKStroke timestamps
- AI event markers on timeline
- Branch compare side-by-side split
- Version snapshots (Tier B)
- **Build & commit: "phase2: group-d replay"**

### 5. Group E — Voice Extensions
- Point + talk (lasso context while listening)
- Dictate math (scripted transcript → LaTeX chip)
- Read-aloud (Tier B)
- **Build & commit: "phase2: group-e voice"**

### 6. Group F — Classroom
- Classes tab in Library
- Mock class "STATS 2D03" with worked examples
- Fork to my notebook
- Role toggle (Student/Instructor)
- Live lecture mode (Tier B)
- Misconception dashboard (Tier B)
- **Build & commit: "phase2: group-f classroom"**

### 7. Group G — Workflow
- PDF import (Files picker → PDFKit backgrounds → ink on top)
- Templates (Problem Set, Proof, Lecture Notes, Exam Practice)
- Split view (Tier B)
- Desktop handoff (Tier B)
- **Build & commit: "phase2: group-g workflow"**

### 8. Seed Data Extension
- Two chat threads (one scoped to × step)
- Predict-then-reveal exchange
- Two insights
- One linked graph card
- Replayable page 1
- One class with two worked examples
- **Build & commit: "phase2: seed-data"**

### 9. Final Verification
- Clean build
- Simulator screenshots
- Visual language audit
