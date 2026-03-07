# Framer: Detailed Roadmap & Execution Plan (2026)

---

## Overview

This document provides week-by-week execution details for the 12-month roadmap outlined in PRODUCT_REVIEW.md. It's designed for developers, designers, and the product lead to track progress and adjust priorities based on signals.

---

## Q1 2026: Foundation & Validation (Jan 1 - Mar 31)

### Theme: "Ship the Basics, Validate Market"

**Goals:**
- Complete technical foundation (undo/redo, caption-as-layer)
- Validate product-market fit signals (1% of target market = 5,000 photographers)
- Establish metrics and feedback loops
- Launch on social media

---

### Week 1-2: Caption-as-Layer Refactoring (In Progress)

**Owner:** Engineering
**Status:** 80% complete per recent commits

**Tasks:**
- [x] Add CaptionLayerParams to CompositionLayer
- [x] Remove caption/font fields from ProcessingConfig
- [x] Update CaptionRenderer signature
- [x] Handle .caption case in BorderRenderer.applyLayers
- [ ] Update YAMLConfig for caption layer encoding/decoding
- [ ] Update CLI ProcessCommand to build caption layers
- [ ] Update UI LayerListSection with caption controls
- [ ] Update all tests (102 total)

**Success Criteria:**
- `swift build && swift test` passes all tests
- Live preview works with multiple caption layers in stack
- Presets load/save with caption layers correctly
- No regression in export quality

**Deliverable:**
```
feat: caption-as-layer refactoring complete
- Caption now a first-class composition layer
- Removes special-case caption handling from ProcessingConfig
- Enables caption reordering, multiple captions per image
```

---

### Week 3-4: Undo/Redo System

**Owner:** Engineering
**Effort:** 2 weeks
**Estimated Lines:** 300-400

**Design:**
- Each layer modification (edit params, reorder, delete) creates undo action
- Max 20 undo steps (memory limit)
- AppState tracks `undoStack` and `redoStack`
- Menu items: Edit → Undo, Edit → Redo, keyboard shortcuts CMD+Z, CMD+Shift+Z

**Tasks:**
1. Add undo stacks to AppState
   ```swift
   @MainActor
   final class AppState {
       var undoStack: [ProcessingConfig] = []
       var redoStack: [ProcessingConfig] = []
       func undo() { ... }
       func redo() { ... }
   }
   ```

2. Capture state before each layer mutation in LayerListSection
   ```swift
   func removeLayer(at index: Int) {
       appState.captureUndoState()  // Save current config
       layers.remove(at: index)
   }
   ```

3. Add undo/redo menu items in FramerApp
4. Wire keyboard shortcuts (CMD+Z, CMD+Shift+Z)
5. Show undo/redo in Edit menu (enable/disable based on stack state)

**Success Criteria:**
- Edit menu shows "Undo/Redo" with correct state
- Keyboard shortcuts work (CMD+Z undoes, CMD+Shift+Z redoes)
- Max 20 states kept (memory efficient)
- Redo clears when user makes new change after undo

**Deliverable:**
```
feat: add undo/redo for layer editing
- Undo/redo up to 20 states
- Keyboard shortcuts CMD+Z / CMD+Shift+Z
- Memory efficient with state limit
```

---

### Week 5: First-Time Experience (FTX) Flow

**Owner:** Product + Design + Engineering
**Effort:** 1 week
**Goal:** Reduce bounce rate for new users

**Current Problem:**
- App opens empty (blank canvas)
- No guidance on how to start
- Users don't understand "layers"

**Solution:**
1. App launches with embedded sample JPEG (sunset photo, 3MB)
   - Save to Bundle as `SamplePhoto.jpg`
   - Auto-load on first launch only

2. 3-step inline tutorial (if no photos added):
   - Step 1: "Drag a photo or click + to add"
   - Step 2: "Adjust layers on the right"
   - Step 3: "Click Export Selected to save"

3. Tooltip system
   - Hover over layer labels → "Border: adds a frame around the photo"
   - Hover over icons → explains what each layer does

**Tasks:**
1. Create sample photo (or find CC-licensed sunset image)
2. Add `SamplePhoto.jpg` to Bundle resources
3. Modify AppState to load sample on first launch
   ```swift
   func loadSamplePhotoOnFirstLaunch() {
       if library.isEmpty && !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
           if let url = Bundle.main.url(forResource: "SamplePhoto", withExtension: "jpg") {
               addPhotos(from: [url])
               UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
           }
       }
   }
   ```

4. Add tooltip system to LayerRow
   - Hover state → small popover explains layer
   - Persist "hide tooltips" preference

**Success Criteria:**
- New users see sample photo on launch
- 3-step flow is visible
- Tooltips appear on hover
- Users understand "layers" concept

**Deliverable:**
```
feat: first-time experience with sample photo and tooltips
- Auto-load sample sunset photo on first launch
- Inline tooltip system explaining each layer
- 3-step quick-start guide
```

---

### Week 6: YouTube Content Creation (Ongoing)

**Owner:** Product + Video
**Effort:** Part-time (2-3 hours per video)

**Goal:** Drive organic discovery, validate market demand

**Video 1: "Batch Frame 100 Photos in 30 Seconds" (8 min)**
- Hook: "Stop framing photos manually in Photoshop"
- Show: 100 Instagram photos → 1 click export → all framed with borders/captions
- Features: Preset system, batch export, EXIF captions
- CTA: GitHub link, mention free + open source
- Publishing: YouTube (Framer channel), Reddit r/photography

**Video 2: "Auto-Caption from Camera EXIF" (6 min)**
- Hook: "Your camera already stores all this data"
- Show: JPEG with EXIF → auto-extract camera/lens/ISO/date → render in caption
- Features: Template tokens, date formatting, font styling
- CTA: GitHub

**Video 3: "macOS App vs CLI Tool" (7 min)**
- Hook: "Use Framer in your scripts or app"
- Show: CLI batch export, preset loading, chaining with other tools
- Features: Multi-worker processing, YAML presets, metadata preservation
- CTA: GitHub docs

**Metrics to Track:**
- Views, click-through rate to GitHub
- Comments (feature requests, pain points)
- Subscriber count
- Source: YouTube, Reddit, ProductHunt

**Success Criteria:**
- >5,000 total views across 3 videos
- >50 GitHub stars (from video traffic)
- >10 substantive comments with feedback
- >20 signups to email list (if added)

---

### Week 7-8: Metrics & Analytics Framework

**Owner:** Engineering
**Effort:** 1 week
**Goal:** Measure product-market fit signals

**What to Track:**
1. **Activation Metrics** (event-based)
   - App launch
   - First photo import
   - First export
   - Preset save
   - Batch export (3+ photos)

2. **Usage Metrics** (weekly/monthly)
   - DAU, WAU, MAU
   - Average photos exported per user per week
   - Preset reuse rate (% of exports using presets)
   - Batch export rate (% of exports with 3+ photos)

3. **Retention Metrics**
   - Day 1, Day 7, Day 30 retention
   - Churn rate per cohort
   - Return users (launched >1 time)

4. **Quality Metrics** (optional)
   - Export success rate
   - Crash rate
   - Feature usage (layer types used per export)

**Implementation:**
- Add optional analytics telemetry (opt-in, privacy-first)
- Use Posthog (free tier) or Mixpanel
- Send events: app launch, import, export, preset actions
- Do NOT send image data, file paths, or user content

**Tasks:**
1. Set up Posthog account (free tier)
2. Add telemetry library to FramerApp
3. Create events for key actions
4. Build dashboard: DAU/WAU/MAU, conversion funnel
5. Document privacy policy (what data we collect)

**Success Criteria:**
- Dashboard shows daily signups and active users
- Can measure "Day 7 retention" cohort
- Privacy policy published (transparency)
- <1% performance overhead from telemetry

**Deliverable:**
```
feat: optional analytics to measure product-market fit
- Posthog integration for activation/retention metrics
- Privacy-first (no image or file data)
- Dashboard: DAU/WAU/MAU, conversion funnel
```

---

### Week 9-10: Social Media & Community Launch

**Owner:** Marketing
**Effort:** 2 weeks (ongoing)

**Goal:** Build awareness, engage target audience

**Channels to Launch:**
1. **Twitter (@FramerApp)**
   - Share weekly tips ("Did you know: {{camera}} template auto-fills from EXIF")
   - Retweet user photos framed with Framer
   - Engage with #photography #photographers community
   - Target: 500 followers by end of Q1

2. **Reddit (r/photography, r/Lightroom, r/MacApps)**
   - "I built a tool to batch frame photos—free and open source"
   - Answer questions about use cases, compare to Lightroom
   - Target: 100+ upvotes, 20+ comments with feature ideas

3. **Email List (optional)**
   - Landing page: "Get Framer tips + preset packs emailed weekly"
   - Capture 50+ emails from YouTube viewers
   - Send weekly emails (presets, tips, updates)

4. **GitHub Discussions**
   - Enable GitHub Discussions for feature requests
   - Respond to all issues < 24 hours
   - Monthly digest of top requests

**Content Calendar (Q1):**
- Week 9: "Framer is now open source on GitHub"
- Week 10: "Batch export 100 photos in 30 seconds"
- Week 11: "Auto-caption with EXIF data"
- Week 12: "5 presets to get you started"

**Success Criteria:**
- 500+ Twitter followers
- 100+ upvotes on Reddit intro post
- 50+ email subscribers
- 5+ feature requests with >10 upvotes each

---

### Week 11-12: Q1 Review & Retrospective

**Owner:** Product Lead
**Effort:** 1 week

**Review Metrics:**
- Total downloads/signups (target: 1,000-5,000)
- YouTube views (target: 5,000+)
- Retention rate (target: >30% Day 7)
- Feature most requested (feedback analysis)

**Decisions to Make:**
1. **Is product-market fit signaling positive?**
   - If Yes (>2,000 MAU, >40 NPS) → Proceed to Q2 as planned
   - If No (<1,000 MAU, <30 NPS) → Pivot to Lightroom-only or B2B

2. **Should we prioritize Lightroom plugin in Q2?**
   - If Yes → Start design/API exploration this week
   - If No → Continue mobile/UI improvements

3. **What feature request is most common?**
   - Adjust Q2 roadmap accordingly

**Deliverable:**
```
Retrospective: Q1 2026 Product-Market Fit Signals
- Downloads: [actual]
- Day 7 retention: [actual]%
- Feature requests: [top 3]
- Next quarter pivot or proceed: [decision]
```

---

## Q2 2026: Discoverability & Core Features (Apr 1 - Jun 30)

### Theme: "Build Features Users Ask For, Enable Distribution"

**Goals:**
- Implement Photo.app library integration (major usability improvement)
- Add layer thumbnails/preview (reduce UI complexity)
- Lightroom plugin design phase (preparation)
- 50,000+ downloads total

---

### Week 13-14: Photo.app Library Integration

**Owner:** Engineering
**Effort:** 3 weeks

**Goal:** Users can browse and import from macOS Photos.app instead of file picker

**Current State:**
- File picker forces users to navigate folders manually
- Photos.app is where most photographers store originals
- Missing Photos framework integration

**Solution:**
1. Add Photos framework to FramerApp
2. Create `PhotoLibraryBrowser` view
   - Shows recent photos grid (similar to Photos.app)
   - Multi-select support
   - Smart albums: Favorites, Last 30 Days, etc.

3. Update AppState to import from Photos.app
   ```swift
   func addPhotosFromLibrary(_ assets: [PHAsset]) {
       let manager = PHImageManager.default()
       for asset in assets {
           manager.requestImageData(for: asset) { imageData, _, _, _ in
               // Save to temp, add to library
           }
       }
   }
   ```

4. Fallback: Keep file picker for non-Photos.app sources

**Tasks:**
1. Import Photos framework
2. Design PhotoLibraryBrowser UI
3. Implement multi-select grid
4. Handle permissions (NSPhotoLibraryUsageDescription)
5. Add "Recent" smart album
6. Test with 10k+ photos in library

**Success Criteria:**
- Users can browse Photos.app without file picker
- Multi-select imports 10+ photos at once
- Permissions dialog is clear
- App doesn't hang with large libraries (>10k photos)

**Deliverable:**
```
feat: photo library integration with Photos.app
- Browse Photos.app library in-app
- Multi-select import from smart albums
- Permissions dialog
- Faster import workflow
```

---

### Week 15-16: Layer Thumbnails & Composition Preview

**Owner:** Design + Engineering
**Effort:** 2 weeks

**Goal:** Users understand what each layer does before export

**Problem:**
- Layer names alone don't explain visual effect
- New users can't visualize "border" vs "padding" vs "canvas"

**Solution:**
1. **Layer Thumbnail:** Each layer row shows a small (120x120) preview
   - Border layer: Shows frame thickness, color
   - Padding layer: Shows fill color/gradient
   - Caption layer: Shows text sample ("MON '23")
   - Canvas layer: Shows dimensions (1080x1350)
   - Orientation layer: Shows 90° rotation indicator

2. **Interactive Composition Preview:**
   - New "Composition" section in SettingsPanel
   - Shows final output (1000px wide) with live update
   - Slider to compare before/after

**Technical:**
- Render layer preview async (don't block UI)
- Cache preview images (update on layer change)
- Use same BorderRenderer pipeline as live preview

**Tasks:**
1. Add `previewImage` computed property to each CompositionLayer type
2. Create `LayerThumbnailView` component
3. Render thumbnail in LayerRow
4. Add composition preview to SettingsPanel
5. Cache previews to avoid re-rendering

**Success Criteria:**
- Each layer shows thumbnail (2-3px latency)
- Composition preview updates in <300ms
- Thumbnails are accurate (match final output)
- Memory usage doesn't spike (cache size limit)

**Deliverable:**
```
feat: layer thumbnails and composition preview
- Visual preview of each layer's effect
- Live composition preview (before/after)
- Reduces confusion for new users
```

---

### Week 17: Preset Import/Export

**Owner:** Engineering
**Effort:** 1 week

**Goal:** Users can share presets with colleagues, build community presets

**Current State:**
- Presets are saved locally in ~/Library/Application Support/Framer/
- No way to export/share them

**Solution:**
1. **Export Preset:**
   - Right-click preset → "Export..."
   - Saves as `.framer-preset` (JSON file)
   - File includes: preset name, layers, output settings, thumbnail

2. **Import Preset:**
   - Drag-drop `.framer-preset` to app
   - Or: File menu → "Import Preset..."
   - Validates JSON, adds to presets list

3. **Share Preset:**
   - In Preset Manager, add "Share" button
   - Opens sharing sheet (email, AirDrop, etc.)

**Tasks:**
1. Add export function to PresetStore
   ```swift
   func export(_ preset: Preset) -> Data {
       return try JSONEncoder().encode(preset)
   }
   ```

2. Add import validation
   - Check JSON structure
   - Validate layer types
   - Prevent duplicate names

3. Add UI for import/export
   - Context menu in PresetManagerView
   - Drag-drop support in LibrarySidebar

4. Test with 50 different presets

**Success Criteria:**
- Can export preset as `.framer-preset` file
- Can import and use exported preset
- Validation prevents corrupt imports
- Share sheet works (AirDrop, email)

**Deliverable:**
```
feat: import/export presets for sharing
- Export preset to .framer-preset file
- Import from drag-drop or file picker
- Validation and error handling
- Community preset sharing enabled
```

---

### Week 18-19: Lightroom Plugin Design (Research Phase)

**Owner:** Product + Engineering
**Effort:** 2 weeks (design only, no code)

**Goal:** Map out technical feasibility and architecture for Lightroom plugin

**Research Tasks:**
1. **Study Lightroom Plugin API**
   - Lightroom's LUA API documentation
   - Plugin sandbox restrictions
   - Photo export capabilities

2. **Design Architecture:**
   ```
   Lightroom Plugin (LUA)
       → Exports photo to temp folder
       → Calls Framer CLI with preset
       → Imports result back to Lightroom
   ```

3. **Study Alternatives:**
   - Direct export dialog in Lightroom
   - External editor integration
   - Publish service (auto-upload)

4. **Identify Blockers:**
   - Can plugin invoke external app (Framer)?
   - Can plugin re-import edited photos?
   - Performance: is CLI fast enough?

5. **Design Mockups:**
   - Lightroom toolbar button → "Frame in Framer"
   - Preset picker inside Lightroom
   - Progress bar for export

**Deliverable:**
```
Design Doc: Lightroom Plugin Architecture
- Plugin flow: export → process → import
- Estimated effort: 6 weeks
- Blockers and mitigations
- Alternative approaches
```

---

### Week 20-21: Watermark Layer

**Owner:** Engineering
**Effort:** 2 weeks

**Goal:** Users can add watermarks (text or image) to protect photos

**Design:**
- New CompositionLayer type: `.watermark(WatermarkLayerParams)`
- Support text watermarks ("Copyright 2026") and image watermarks (PNG)
- Positioning: top-left, top-right, bottom-left, bottom-right, center
- Opacity control (0-100%)

**Tasks:**
1. Add `WatermarkLayerParams` struct
   ```swift
   public struct WatermarkLayerParams: Codable, Equatable {
       public enum WatermarkType {
           case text(String, fontColor: CodableColor)
           case image(URL)  // Path to PNG
       }
       public var type: WatermarkType
       public var position: WatermarkPosition  // .topLeft, .topRight, etc.
       public var opacity: Double  // 0-1
       public var scale: Double  // 0.1-1.0
   }
   ```

2. Implement `WatermarkRenderer`
   - Render text with CoreText
   - Load and composite image watermark
   - Apply opacity blend mode

3. Add to `BorderRenderer.applyLayers` switch
4. Add UI controls in LayerListSection
5. Update presets (add watermark examples)

**Success Criteria:**
- Text watermarks render with custom fonts
- Image watermarks scale correctly
- Opacity blending looks professional
- Performance: <100ms per watermark

**Deliverable:**
```
feat: watermark layer for text and image protection
- Text watermarks with custom fonts and colors
- Image watermark support (PNG)
- Positioning and opacity controls
- Professional watermarking workflow
```

---

### Week 22-23: 20 New Default Presets

**Owner:** Design + Product
**Effort:** 2 weeks (part-time)

**Goal:** Reduce "blank canvas" problem, show versatility

**Preset Strategy:**
- 5 category groups (10 presets per category)
- Each preset is a 3-4 layer composition
- Visually distinct (different colors, styles, layouts)

**Categories:**
1. **Minimal** (5 presets): Thin borders, white padding
   - "Clean White", "Clean Black", "Clean Gray", "Clean Blue", "Clean Warm"

2. **Social Media** (5 presets): Instagram, TikTok, Twitter dimensions
   - "Instagram 4:5", "TikTok 9:16", "Twitter 16:9", "Square 1:1", "Stories"

3. **Vintage** (5 presets): Film-inspired with textures
   - "Film 1970s", "Film 1980s", "Polaroid", "Slide", "Kodachrome"

4. **Professional** (5 presets): Print-ready with metadata
   - "Print 10x15", "Print 8x10", "Print 5x7", "Magazine", "Portfolio"

Each preset:
- Has a visible thumbnail (rendered from sample image)
- Includes description: "4:5 ratio for Instagram feed"
- Shows layer count and output format

**Tasks:**
1. Design 20 layer-based presets in LayerListSection
2. Render thumbnail for each (using test image)
3. Export as JSON to defaults directory
4. Update PresetStore to load from defaults
5. Test all presets render correctly

**Success Criteria:**
- 20 presets load without errors
- Each has unique visual style
- Thumbnails are legible (100x100px)
- Presets cover diverse use cases

**Deliverable:**
```
feat: 20 new default presets for quick-start
- Minimal, Social Media, Vintage, Professional categories
- Preset thumbnails for visual discovery
- Diverse styles and dimensions
```

---

### Week 24: ProductHunt Launch & Q2 Review

**Owner:** Product + Marketing
**Effort:** 1 week

**Goal:** Drive viral awareness, collect feedback

**Launch Plan:**
- Post on ProductHunt on Tuesday/Wednesday (high traffic)
- Get "Ship" (makers community) to upvote
- Respond to all comments < 2 hours
- Highlight unique value: EXIF captions, batch processing, CLI

**Messaging:**
- Headline: "Framer: Batch frame 100 photos in 30 seconds"
- Description: "Free, open-source macOS app for adding borders, EXIF captions, and overlays to photos—inspired by vintage printing"
- Gallery: Before/after examples from user presets
- Video: 1-min demo of batch export

**Success Criteria:**
- >100 upvotes on ProductHunt
- >500 website visits from ProductHunt
- 20+ feature comments/suggestions
- 1,000+ signups from ProductHunt

**Metrics Review:**
- Total downloads: 50,000+ (target)
- Day 7 retention: >35% (target: >30%)
- Photo.app integration adoption: >60% of users
- Top feature request: [analyze comments]

**Decision Point:**
- Lightroom plugin Y/N? (High effort, so decide now)
- Additional marketing channels?
- Adjust Q3 priorities based on feedback

---

## Q3 2026: Plugin & Premium Features (Jul 1 - Sep 30)

### Theme: "Expand Distribution, Monetize, Build Community"

**Goals:**
- Lightroom plugin (public beta or release)
- Launch freemium model (premium presets)
- 200,000+ downloads total

---

### Week 25-32: Lightroom Plugin Development (8 weeks)

**Owner:** Engineering (new team member ideally)
**Effort:** 8 weeks full-time
**Architecture:** LUA + CLI integration

**Phases:**
1. **Weeks 25-26:** Setup & basic export
   - LUA development environment
   - Plugin template project
   - Photo export to temp folder
   - Invoke Framer CLI with preset

2. **Weeks 27-28:** Preset integration
   - Dropdown: select Framer preset
   - Pass preset name to CLI
   - Result goes to destination folder

3. **Weeks 29-30:** Re-import to Lightroom
   - Framed photo imported back to Lightroom
   - Added to new collection
   - Stacked with original

4. **Weeks 31-32:** Polish, testing, Adobe submission
   - Lightroom marketplace submission
   - A/B testing: plugin flow vs. app flow
   - Performance benchmarks
   - User testing with Lightroom users

**Deliverable:**
```
feat: Lightroom plugin for one-click framing
- Export photo from Lightroom
- Process with Framer preset
- Re-import framed result
- Lightroom marketplace listing
```

---

### Week 33-34: Freemium Monetization

**Owner:** Product + Engineering
**Effort:** 2 weeks

**Freemium Model:**
- **Free Tier:** 5 default presets, basic editing, CLI access
- **Premium Tier:** $9.99/month
  - 50+ community presets
  - Custom watermarks (text + image)
  - Batch export profiles (save export settings)
  - Advanced overlays (100+ textures)
  - Priority support

**Implementation:**
1. Add subscription detection to AppState
   ```swift
   @MainActor
   final class AppState {
       var isPremium = false  // Check with StoreKit
       var premiumFeatures: [String] = []  // ["watermarks", "presets", ...]
   }
   ```

2. Use StoreKit 2 (Apple's subscription framework)
   - Monthly subscription product
   - Free trial (14 days recommended)
   - Restore purchases

3. Gate premium features
   - Premium presets folder (locked UI)
   - Watermark layer (locked until upgrade)
   - Advanced overlays (locked)

4. Paywall UI
   - "Upgrade to Premium" sheet
   - Show benefits
   - Free trial offer

**Pricing Strategy:**
- $9.99/month (or $99/year = 17% discount)
- Target: 500 subscribers = $50k/year (Phase 2 revenue)
- Free tier attracts users; premium drives revenue

**Success Criteria:**
- StoreKit integration works (can purchase on test device)
- Premium features properly gated
- Free trial conversion tracked
- <2% churn for premium subscribers

**Deliverable:**
```
feat: freemium monetization with StoreKit
- Free: 5 presets + basic editing
- Premium: 50+ presets + watermarks + overlays
- $9.99/month subscription
- 14-day free trial
```

---

### Week 35-36: Community Preset Library

**Owner:** Product + Design
**Effort:** 2 weeks

**Goal:** Build peer-to-peer preset sharing, reduce "blank canvas"

**Platform:**
- GitHub discussions or separate website (framer.community?)
- Users upload `.framer-preset` files
- Voting system (upvote good presets)
- Tags: #vintage, #minimal, #instagram, #print

**Workflow:**
1. User creates preset → Exports to `.framer-preset` file
2. Posts in community (GitHub/website)
3. Others download and import via drag-drop
4. Most popular presets featured in-app under "Community"

**Implementation:**
- GitHub repository: `framer/presets` (community fork)
- Curated section in PresetManagerView: "Popular Community Presets"
- Download + auto-import button

**Success Criteria:**
- 50+ community presets created
- 10+ high-quality presets with >20 downloads each
- Community engagement (comments, feedback)

---

### Week 37-39: B2B Pilot Program

**Owner:** Product (sales/partnerships)
**Effort:** 3 weeks

**Goal:** Identify high-value customers (photo labs, studios)

**Targets:**
1. **Photo Labs** (Mpix, Artifact Uprising, PrintNinja)
   - Need: Batch watermark + resize for print
   - Use case: Photographer submits 100 photos → lab auto-processes with studio branding

2. **Wedding Photography Studios** (WPJA, Fearless Photographers)
   - Need: Batch frame + caption (date, couple name)
   - Use case: Client receives 500 wedding photos with custom borders

3. **Content Creator Tools** (Descript, Frame.io)
   - Need: Framer backend for their batch processing
   - Use case: Video frame extraction → batch frame → thumbnail grid

**Approach:**
1. Identify 10-15 target companies
2. Reach out with pitch: "We can process your batch framing needs at scale"
3. Offer free trial (process 100 photos, free)
4. Propose pricing: $500-2000/month per organization

**Deliverable:**
```
B2B Pilot Program: 5+ interested leads
- Wedding photography studios
- Print labs
- Creator tools
```

---

### Week 40: Q3 Review & Roadmap Planning

**Owner:** Product Lead

**Metrics:**
- Lightroom plugin downloads (target: 5,000+)
- Premium subscribers (target: 100+)
- Community presets created (target: 50+)
- B2B leads in pipeline (target: 5+)

**Decision:**
- Is plugin performing well enough to continue investment?
- Should we hire B2B sales person in Q4?
- Adjust Year 2 strategy based on results

---

## Q4 2026: Scale & Year-End (Oct 1 - Dec 31)

### Theme: "Consolidate Gains, Plan for Year 2"

**Goals:**
- 500,000+ total downloads
- 500+ premium subscribers
- 3+ B2B customers signed
- Plan Year 2 strategy

---

### Week 41-44: Plugin Optimization & Support

**Owner:** Engineering
**Effort:** 2 weeks (ongoing support)

**Focus:**
- Fix bugs from user feedback
- Optimize performance (export speed)
- Add requested features (if <1 week each)
- Monitor plugin ratings

---

### Week 45-48: B2B Customer Onboarding & Case Studies

**Owner:** Sales + Product
**Effort:** 4 weeks

**Goal:** Land 3+ B2B customers, create case studies

**For Each Customer:**
1. Custom integration (API, file watcher, webhook)
2. Training / documentation
3. Monthly check-ins
4. Case study writeup ("How XYZ studio now frames 500 photos/day")

**Success Criteria:**
- 3+ B2B contracts signed
- 2+ case studies published
- Combined B2B ARR: $20k+

---

### Week 49-52: Year-End Review & 2027 Planning

**Owner:** Product Lead + Team
**Effort:** 2 weeks

**Retrospective:**
- What worked in 2026? (Lightroom plugin? Premium tier?)
- What didn't? (Certain features? Marketing channels?)
- User feedback synthesis (top 20 feature requests)

**2027 Strategy (Outline):**
- If PMF validated: Scale acquisition, expand features
- If PMF unclear: Pivot or double down on specific segment (B2B, Lightroom-only, etc.)
- If failed: Graceful sunset or open-source community takeover

**Metrics Summary:**
| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Downloads | 500k | [actual] | [✅/❌] |
| Premium Subs | 500 | [actual] | [✅/❌] |
| NPS | >50 | [actual] | [✅/❌] |
| Monthly Churn | <3% | [actual] | [✅/❌] |
| Lightroom Plugin Installs | 5k | [actual] | [✅/❌] |

---

## Appendix: Detailed Effort Estimates

| Feature | Weeks | Team | Dependencies |
|---------|-------|------|--------------|
| Caption-as-Layer | 2 | Eng | (in progress) |
| Undo/Redo | 2 | Eng | caption layer done |
| FTX + Tooltips | 1 | Design + Eng | - |
| Photo.app Integration | 3 | Eng | - |
| Layer Thumbnails | 2 | Design + Eng | photo.app done |
| Preset Import/Export | 1 | Eng | - |
| Watermark Layer | 2 | Eng | - |
| 20 New Presets | 2 | Design | - |
| Lightroom Plugin | 8 | Eng | - |
| Freemium Monetization | 2 | Eng + Product | - |
| Community Presets | 2 | Product | preset import done |
| B2B Pilot | 3 | Product (sales) | - |
| **Total** | **30 weeks** | **2-3 people** | - |

---

## Resource Plan

**Team Composition:**
- **1x Product Manager:** Strategy, roadmap, customer interviews
- **1-2x Full-Stack Swift Engineers:** Feature development, plugin
- **0.5x Designer:** UI/UX, presets, marketing
- **0.5x Marketing/Community:** Content, social, outreach

**Budget Estimate (Year 1):**
- Salaries: $300k-400k (2-3 people, part-time/contract)
- Tools: $2k (Posthog, design software, etc.)
- Marketing: $5k (content, ads)
- **Total: $307k-407k**

**Revenue Projection (Year 1):**
- Premium subscribers: 500 × $9.99/month × 12 = $60k
- B2B customers: 3 × $1000/month × 6 months = $18k
- **Total: $78k** (break-even not achieved in Year 1)

**Break-Even Plan (Year 2):**
- Premium subscribers: 2,000 × $9.99/month × 12 = $240k
- B2B customers: 10 × $1500/month × 12 = $180k
- **Total: $420k** (covers salary costs)

---

## Success Metrics Dashboard

**Real-Time Tracking (Updated Weekly):**
- Downloads (cumulative)
- MAU (monthly active users)
- Day 7 retention (%)
- Premium subscribers
- Top feature requests (sentiment analysis)

**Monthly Sync:**
- Revenue ($)
- Churn rate (%)
- NPS (score)
- Feature completion status
- B2B pipeline value

**Quarterly Reviews:**
- Roadmap vs. actual (% complete)
- User feedback themes
- Competitive positioning
- Next quarter priorities

---

**Document Version:** 1.0
**Last Updated:** 2026-03-07
**Next Update:** 2026-06-30 (after Q2)
