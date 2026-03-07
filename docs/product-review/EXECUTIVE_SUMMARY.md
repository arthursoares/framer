# Framer: Executive Summary for Decision-Makers

**Date:** March 7, 2026
**Prepared for:** Product team, investors, stakeholders
**Length:** 2 pages
**Status:** READY FOR EXECUTION

---

## The Problem & Solution

### What's the Problem?
Photographers manually frame photos in Photoshop (30 min for 10 photos). Lightroom doesn't have framing tools. Existing tools are slow, complicated, or expensive.

### What's the Solution?
**Framer** — A native macOS app that frames 100+ photos in one click, with auto-filled captions from camera EXIF data (e.g., "Canon 5D | f/2.8 | April 2026").

---

## Current State

| Aspect | Assessment |
|--------|-----------|
| **Product** | ✅ Beta-ready (102 tests, clean architecture) |
| **Technology** | ✅ Swift 5.10, performant, well-designed |
| **Features** | ✅ Complete (presets, batch, layers, EXIF) |
| **User base** | ❌ 0 tracked downloads (invisible to market) |
| **Monetization** | ❌ None (open-source, free) |
| **Distribution** | ❌ GitHub only (wrong channel) |
| **Team** | ⚠️ Solo developer (sustainability risk) |

**Verdict:** Great product, zero go-to-market strategy.

---

## Market Opportunity

### Market Size
- **Total addressable market:** ~10M photographers worldwide
- **Target (Instagram/print):** ~1M photographers
- **Realistic Year 1 target:** 5-50k users (0.5-5% penetration)

### Competitive Position
Framer is **unique** in:
- Batch processing (100 photos in one click)
- EXIF-based auto-captions (photographers love this)
- Free + open-source (removes pricing barrier)
- CLI tool (enables automation)

Framer competes with:
- Lightroom (export-only, not designed for framing)
- Darkroom (iOS-only, less automation)
- Photoshop (10x slower, $55/month)
- Online tools (lossy, slow, not batch)

**Competitive advantage:** Batch + EXIF automation is unique. No direct competitor.

---

## Strategic Recommendation

**Status:** VALIDATION REQUIRED (not execution)

**Do NOT invest heavily in features or marketing until you validate:**
1. Photographers actually want this (user interviews)
2. Batch processing is the key value prop (user research)
3. Distribution channel exists (YouTube, Lightroom plugin, etc.)

**6-Week Validation Plan:**
- 20-30 user interviews with photographers
- 100+ survey responses
- 2-3 YouTube videos measuring viewership
- Analytics setup to track real metrics

**Cost:** $0-200 (mostly time)
**Team:** 0.5 product, 0.25 engineering, 0.25 marketing

**Deliverable:** "Pivot or proceed?" recommendation (April 30, 2026)

---

## 90-Day Roadmap (If Validation is Positive)

### Q1 (Now): Foundation
1. ✅ Caption-as-layer refactoring (2 weeks) — technical cleanup
2. ✅ Undo/redo (2 weeks) — removes friction
3. ✅ YouTube videos (2 weeks) — validate market
4. ✅ Analytics setup (1 week) — measure metrics

**Output:** First users, validated demand signal, YouTube growth

### Q2: Distribution & Growth
1. Photo.app integration (3 weeks) — major UX improvement
2. Layer thumbnails (2 weeks) — reduce UI confusion
3. ProductHunt launch (1 week) — initial awareness
4. Lightroom plugin design (2 weeks) — plan highest-ROI feature

**Output:** 50,000+ downloads, 1,000+ users, Lightroom plugin design complete

### Q3: Monetization & Enterprise
1. Lightroom plugin release (8 weeks) — reach photographers at point of sale
2. Freemium tier launch ($9.99/month) — 50+ presets, premium features
3. B2B partnerships (3 weeks) — photo labs, studios

**Output:** 500 premium subscribers ($60k ARR), 3+ B2B leads

---

## Financial Projections

### Year 1 (2026)

**Revenue:**
- Premium subscribers (500): $60k
- B2B customers (3): $18k
- **Total: $78k**

**Costs:**
- Team (2-3 people): $300-400k
- Tools/marketing: $7k
- **Total: $307-407k**

**Result:** -$229-329k (not profitable Year 1, as expected for venture)

### Year 2 (2027)

**Revenue:**
- Premium subscribers (2,000): $240k
- B2B customers (10): $180k
- **Total: $420k**

**Costs:**
- Team (3-4 people): $350-450k
- Tools/marketing: $10k
- **Total: $360-460k**

**Result:** Break-even to +$60k (profitable, sustainable)

---

## Go/No-Go Criteria

### GO Signals (Proceed with full execution)
- ✅ >40% of surveyed photographers say they'd use Framer
- ✅ >5,000 views on first YouTube video
- ✅ >50% of users do batch exports (3+ photos)
- ✅ >40 NPS score (user satisfaction)
- ✅ Lightroom plugin feasible (no technical blockers)

### NO-GO Signals (Pivot or sunset)
- ❌ <20% interest in Framer (product doesn't resonate)
- ❌ <1,000 views on YouTube (topic doesn't resonate)
- ❌ <30% batch export rate (batching not the value prop)
- ❌ Lightroom plugin rejected twice (distribution blocked)
- ❌ <30 NPS (fundamental UX/product issue)

---

## Immediate Actions (This Week)

**Engineering (Arthur):**
1. [ ] Finish caption-as-layer refactoring (priority)
2. [ ] Set up analytics (Posthog account, SDK)
3. [ ] Create sample photo for first-time experience

**Product/Marketing (Hire 0.5 FTE):**
1. [ ] Write YouTube script & record "Batch Frame 100 Photos" video
2. [ ] Create interview screener (who qualifies as photographer?)
3. [ ] Set up Calendly for user interviews
4. [ ] Draft Reddit/Twitter outreach posts

**Timeline:** Complete by March 31, 2026

---

## Risk Assessment

| Risk | Probability | Mitigation |
|------|------------|-----------|
| **No market demand** | Medium | Validate with interviews ASAP |
| **Lightroom plugin rejected** | Low | Build alternative (Capture One, API) |
| **Competitor launches** | Low | Brand quickly, build community moat |
| **Solo dev burnout** | High | Hire co-founder or team early |
| **Wrong target market** | Medium | Interview diverse photographers (wedding, print, Instagram) |

---

## Success Metrics (Track Monthly)

| Metric | Q1 Target | Q2 Target | Q3 Target |
|--------|-----------|-----------|-----------|
| **Monthly Active Users** | 1k | 25k | 50k |
| **Day 7 Retention** | >30% | >35% | >40% |
| **Batch Export Rate** | >40% | >50% | >60% |
| **NPS Score** | >35 | >45 | >55 |
| **Premium Subscribers** | 0 | 50 | 500 |
| **B2B Revenue** | $0 | $0 | $18k |

---

## Decision Required

**Question:** Should we invest in Framer's go-to-market?

**Recommendation:**
- **YES**, but only after 6-week validation (March 15 - April 30)
- Validation cost: $0-200 + 80 hours of team time
- Decision point: April 30 ("Pivot or proceed?")
- If YES → Full execution on roadmap (team hire, feature dev, marketing)
- If NO → Pivot to B2B-only or gracefully sunset

**Timeline:** 6 weeks validation → 2 weeks hiring → 12 months execution

---

## Bottom Line

Framer has **excellent product foundations** and solves a **real problem**, but has **zero distribution**.

**This is not a product problem.** It's a go-to-market problem.

**Next 6 weeks:** Validate product-market fit with users
**Next 6 months:** Build distribution (Lightroom plugin)
**Next 12 months:** Scale acquisition and monetization

**Expected outcome (if validation succeeds):** $420k ARR by Year 2, sustainable business, 50k+ users.

---

## Questions for the Team

1. **Is the validation plan sufficient?** (What additional research is needed?)
2. **Should we hire additional help for Q1?** (Product/marketing person)
3. **What's our commitment if validation is positive?** (Full team allocation for Lightroom plugin?)
4. **If validation fails, what's the pivot?** (B2B-only? Sunset? Pivot product?)
5. **What metrics would convince us to stop?** (What NPS? What retention? What MAU floor?)

---

## Documents Attached

1. **PRODUCT_REVIEW.md** — Full 10-part strategic analysis
2. **ROADMAP_DETAILED.md** — Week-by-week execution plan (12 months)
3. **MARKET_VALIDATION_PLAN.md** — 6-week user research + YouTube plan
4. **PRODUCT_SUMMARY.md** — One-page quick reference

---

**Recommended Action:**
Schedule 30-min call with team to review this summary + decide on validation investment.

**Timeline:**
Decision by March 10 → Validation starts March 15 → Results by April 30 → Full execution or pivot by May 1.

---

**Prepared by:** Product Strategy Analysis
**Date:** March 7, 2026
**Version:** 1.0 (Ready for review)
**Next revision:** April 30, 2026 (post-validation decision)
