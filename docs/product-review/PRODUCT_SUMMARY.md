# Framer Product Summary: One-Page Reference

---

## What is Framer?

A **native macOS photo processing app** that adds professional borders, captions (with EXIF metadata), and texture overlays to photos. Designed for photographers who shoot for Instagram, print, or portfolios.

**Unique strength:** Batch-process 100+ photos with a single click, auto-fill captions from camera metadata (e.g., "Canon 5D | f/2.8 | ISO 400").

---

## Current State (March 2026)

| Aspect | Status |
|--------|--------|
| **Product maturity** | Beta (features complete, PMF not validated) |
| **Code quality** | High (well-architected, 102 tests) |
| **User base** | Unknown (0 known tracked metrics) |
| **Monetization** | None (open-source, free) |
| **Distribution** | GitHub only (invisible to target market) |
| **Team** | Solo developer (Arthur Soares) |

---

## Market Positioning

| Competitor | Framer's Edge | Framer's Weakness |
|------------|---------------|-------------------|
| **Lightroom** | Batch processing, EXIF captions | No framing tools (export-only) |
| **Darkroom** (iOS) | macOS + CLI, free, offline | Mobile-only, less powerful |
| **Photoshop** | 10x faster, easier, presets | Limited; overkill for framing |
| **Online tools** | Native, fast, no internet needed | Not discoverable; no batch |

**Verdict:** Framer wins on *batch + EXIF automation*, but has **zero distribution channels**.

---

## Product-Market Fit: Not Yet Validated

**PMF is NOT an engineering problem.** Code is solid. **It's a go-to-market problem.**

**Evidence:**
- No organic signups tracked
- No user testimonials
- No viral coefficient (no sharing, referrals)
- Unknown if photographers even want this workflow

**Path to PMF:**
1. ✅ Features are done (layer composition, presets, batch, EXIF)
2. ❌ Need to reach photographers (YouTube, Lightroom integration, Reddit)
3. ❌ Need metrics to prove value (DAU, retention, NPS)
4. ❌ Need one killer distribution channel (e.g., Lightroom plugin)

---

## Strategic Recommendations (TL;DR)

### Immediate (Next 30 Days)
1. **Finish caption-as-layer refactoring** (technical foundation)
2. **Add undo/redo** (removes friction for users)
3. **Publish 1 YouTube video** (validate market exists)
4. **Enable analytics** (track metrics going forward)

### Medium-Term (Months 2-6)
1. **Photo.app integration** (major UX improvement)
2. **Launch on ProductHunt** (initial awareness)
3. **Twitter + Reddit outreach** (community building)
4. **Start Lightroom plugin design** (highest ROI distribution)

### Long-Term (Months 7-12)
1. **Lightroom plugin release** (reach photographers where they work)
2. **Launch freemium tier** ($9.99/month for 50+ presets)
3. **B2B partnerships** (photo labs, studios)

---

## Success Metrics to Track Now

| Metric | Target (Year 1) | Why It Matters |
|--------|-----------------|----------------|
| **Monthly Active Users** | 5,000+ | Proves product is discoverable |
| **Day 7 Retention** | >35% | Proves product is useful |
| **Batch Export Rate** | >40% | Proves unique value (batching) |
| **NPS Score** | >40 | Proves user satisfaction |
| **YouTube Views** | 5,000+ | Validates awareness channel |
| **Lightroom Plugin Installs** | 5,000+ | Validates distribution strategy |

---

## Feature Prioritization (What to Build Next)

### MUST-HAVE (Block adoption)
1. **Photo.app integration** (users expect file picker → library)
2. **Undo/redo** (layer editing too risky without it)
3. **Lightroom plugin** (reaches 80% of target market)

### SHOULD-HAVE (Improve retention)
1. **Layer thumbnails** (reduces UI confusion)
2. **Preset import/export** (enables community)
3. **Watermark layer** (common need)
4. **20 more presets** (reduce "blank canvas" anxiety)

### NICE-TO-HAVE (Delight users)
1. **AI background fill** (complex, niche)
2. **iOS app** (wrong platform for use case)
3. **Social media export** (plugin Instagram integration)

---

## Monetization Model (Recommended)

**Phase 1 (Now):** Free (build user base)

**Phase 2 (Q3 2026):** Freemium
- Free: 5 default presets, basic editing
- Premium: $9.99/month → 50+ presets, watermarks, advanced overlays
- Target: 500 subscribers = $60k/year

**Phase 3 (Year 2):** B2B + Enterprise
- Photo labs, studios, content creators
- White-label backend processing
- Target: 10 customers × $1,500/month = $180k/year

**Year 2 Revenue Goal:** $420k (covers salary costs)

---

## Competitive Moat

Framer's defensible strengths:
1. **EXIF-based captions** (template system is unique)
2. **Batch processing** (no competitor does this well)
3. **Open-source + CLI** (geeks love it, enables automation)
4. **Layer-based composition** (flexible, extensible)

Moat builders:
- Invest in community presets (lock in with ecosystem)
- Lightroom plugin integration (distribution advantage)
- API/SDK for integrators (photo lab software, etc.)

---

## Pivot Indicators (When to Change Course)

If by Q4 2026:
- **<2,000 MAU** → Product doesn't resonate; pivot to Lightroom-only or B2B specialist
- **NPS < 30** → Fundamental design/UX problem; requires redesign
- **<20% batch export rate** → Batching isn't the value prop; simplify for casual users
- **Lightroom plugin rejected twice** → Find alternative (Capture One plugin, or Darkroom web API)
- **No B2B leads** → Market may not exist for studios; focus on consumer only

---

## Resource Requirements

**Team Needed (Year 1):**
- 1x Product Manager (0.5-1 FTE)
- 1-2x Swift Engineers (1-1.5 FTE)
- 0.5x Designer (part-time)
- 0.5x Marketing (part-time)

**Budget: $300k-400k** (salaries + tools + marketing)

**Revenue 2026:** $78k (doesn't break even)
**Revenue 2027:** $420k (covers costs, profitable)

---

## One-Sentence Elevator Pitch

**"Framer is to photo framing what Lightroom is to editing: fast, batch-friendly, and makes photographers' lives easier."**

Or: **"Frame 100 Instagram photos in 30 seconds instead of 30 minutes in Photoshop."**

---

## Key Documents

1. **PRODUCT_REVIEW.md** — Full strategic analysis (parts 1-10)
2. **ROADMAP_DETAILED.md** — Week-by-week execution plan (12 months)
3. **PRODUCT_SUMMARY.md** — This document (quick reference)

---

## Quick Links

- **GitHub:** https://github.com/arthursoares/framer
- **License:** MIT (open-source)
- **Swift Version:** 5.10+
- **macOS Minimum:** 14.0
- **Platforms:** macOS (app), CLI, Lightroom (plugin TBD)

---

## Red Flags 🚩

1. **No distribution channels** — Product doesn't exist in photographers' workflows
2. **No analytics** — Can't measure if product is working
3. **No user feedback** — Don't know what photographers actually want
4. **Solo developer** — High risk if person leaves or burns out
5. **No revenue model** — Unsustainable long-term

**All fixable with execution.** This is not a product problem; it's a go-to-market problem.

---

## Green Lights ✅

1. **Clean architecture** — Well-written code, testable, extensible
2. **Unique value** — EXIF captions + batch processing is unique
3. **Real problem solved** — Photographers actually do frame photos manually
4. **Multiple distribution paths** — App, Lightroom plugin, CLI, B2B
5. **Monetization ready** — Clear path to $400k+ ARR

---

## Next Steps (This Week)

- [ ] Finish caption-as-layer refactoring
- [ ] Set up analytics (Posthog or Mixpanel)
- [ ] Create sample photo for FTX
- [ ] Record 1 YouTube video (8-10 min)
- [ ] Post on r/photography with GitHub link
- [ ] Measure response (signups, NPS, feature requests)

---

**Updated:** March 7, 2026
**Version:** 1.0
**Owner:** Product Strategy
**Status:** Ready for execution
