# Framer: Market Validation & User Research Plan

---

## Objective

Before investing in Lightroom plugins, B2B sales, or monetization, we need to **validate** that photographers actually want this product and understand their pain points.

**Goal:** Conduct 20-30 user interviews and collect 100+ responses to validate or pivot.

**Timeline:** 6 weeks (March 15 - April 30, 2026)

---

## Research Questions

### Primary Questions
1. **Do photographers manually frame/border photos today?** (How many? How often? How much time?)
2. **What tools do they use now?** (Lightroom plugins, Photoshop, online tools, manual, none?)
3. **What's broken about current solutions?** (Too slow? Too expensive? Too hard? Not enough control?)
4. **Would Framer solve that problem?** (Would they use it? At what price? How often?)
5. **Where do they discover tools?** (YouTube? Lightroom marketplace? Reddit? Word-of-mouth?)

### Secondary Questions
6. **What's the ideal workflow?** (App? Lightroom plugin? CLI? Web?)
7. **What photo types do they frame?** (Instagram? Print? Portfolio? Wedding? Product?)
8. **How many photos per session?** (1? 10? 100? Helps us understand batch value)
9. **Would they pay?** (Free? $5/month? $50 one-time? $5 per export?)
10. **What features matter most?** (Presets? EXIF captions? Batch? Watermarks?)

---

## Phase 1: User Interviews (Weeks 1-3)

### Target Participants (20-30 interviews)

**Segment 1: Instagram Photographers (8-10 people)**
- Post photos to Instagram regularly (1-10x per week)
- Care about consistency/branding
- Likely to batch-process

**Segment 2: Wedding/Event Photographers (5-8 people)**
- Deliver 100-1000 photos per event
- Add metadata/captions (couple name, date, etc.)
- Heavy batch processing need

**Segment 3: Print/Portfolio Photographers (5-8 people)**
- Sell prints or create portfolios
- Care about framing/presentation
- May not do heavy batch

**Segment 4: Photo Educators/Content Creators (3-5 people)**
- Create tutorials, YouTube content
- Use Framer in workflows
- Tech-savvy, early adopters

### Recruitment Strategy

**Where to find photographers:**
1. **Reddit:** r/photography, r/Lightroom, r/photography_critique
   - Post: "User research: I built a photo framing tool, want to talk about your workflow?"
   - Expect: 5-10 responses from engaged users

2. **Instagram:** Photography communities
   - DM photographers with 1k-100k followers in your niche
   - Offer: "30-min feedback call, I'll share beta access"
   - Expect: 5-10 responses

3. **Photography Forums:** Fred Miranda, DPReview, Cameraside
   - Post introduction + link to survey/Calendly
   - Expect: 3-5 responses

4. **Twitter:** #photography #photographers communities
   - Tweet: "Building a tool to frame photos faster—want to chat?" + Calendly link
   - Expect: 3-5 responses

5. **Personal Network:** Friends, colleagues, past customers
   - Direct email + Calendly
   - Expect: 5-10 responses

### Interview Format

**Duration:** 30-45 minutes (Zoom)

**Structure:**
1. **Icebreaker (5 min):** "Tell me about your photography"
2. **Current workflow (10 min):** "Walk me through how you frame photos today"
   - Screen sharing (if they show their process)
   - Pain points surface naturally
3. **Framer demo (8 min):** Show YouTube video or live demo
   - Watch their reaction (interested? Confused? Excited?)
4. **Feedback (10 min):** "Would you use this? What would make it better?"
   - Pricing, features, distribution
5. **Offer (2 min):** "Want to be a beta tester?"
   - Get email, schedule follow-up

**Research Note:** Record responses in shared spreadsheet (Notion/Airtable)
- Name, photo type, current tool, pain points, interest level, email

### Interview Script

```
Hi [Name], thanks for taking the time. I built a tool called Framer
that helps photographers batch-process and frame photos. I'd love to
hear about your current workflow and get your honest feedback.

1. Can you walk me through how you currently add borders/frames to photos?
   - Which tool do you use?
   - How long does it take per photo?
   - Is it annoying? Why/why not?

2. How many photos do you frame per session?
   - 1-5? 5-50? 50+?

3. [Show demo] Here's Framer. It lets you batch-process photos, auto-fill
   captions from camera data, and save presets. What do you think?
   - Would you use this?
   - What's missing?
   - Price you'd pay?

4. Where would you discover a tool like this?
   - YouTube? Lightroom marketplace? Reddit?

5. Can I put you on the beta waitlist?
```

---

## Phase 2: Survey (Weeks 2-4)

**Parallel with interviews:** Run online survey to reach 100+ photographers

### Survey Platform
- **Typeform** or **Airtable Form** (free tier)
- **Distribution:** Reddit post, Twitter, Instagram, email

### Survey Questions (10-12 questions, 5-8 min)

```
1. Do you frame/border your photos?
   □ Yes, always
   □ Yes, sometimes
   □ Never

2. What tool do you use? (multi-select)
   □ Lightroom (export only)
   □ Photoshop
   □ Online tool (Canva, Darkroom, etc.)
   □ Manual (don't frame)
   □ Other: ___

3. How many photos do you frame per month?
   □ 0-10
   □ 10-50
   □ 50-200
   □ 200+

4. What's your biggest pain point? (open text)
   ___________________

5. How long does it take to frame 10 photos?
   □ <5 min
   □ 5-15 min
   □ 15-30 min
   □ 30+ min

6. What matters most to you? (rank 1-5)
   - Speed
   - Ease of use
   - Customization
   - Preset library
   - Batch processing

7. Would you use Framer?
   □ Yes, definitely
   □ Maybe
   □ Probably not
   □ Not sure

8. What price would you pay?
   □ Free
   □ $5/month
   □ $10/month
   □ $50 one-time
   □ Won't pay

9. What photo type? (multi-select)
   □ Instagram
   □ Print
   □ Wedding/event
   □ Product
   □ Portfolio
   □ Other

10. What would make Framer better? (open text)
    ___________________
```

**Goal:** 100+ responses
**Expected response rate:** 5-10% (so 1,000-2,000 people see survey)
**Timeline:** 2-3 weeks of promotion

---

## Phase 3: Competitive Research (Week 2)

### Tools to Evaluate

**Lightroom Plugins:**
- Search Lightroom marketplace for "border," "frame," "caption"
- Evaluate: Do any exist? Are they popular? What do reviews say?
- Action: Download/try 3 most popular plugins
- Document: Features, pricing, user sentiment

**macOS Apps:**
- Search: "photo frame macOS app"
- Evaluate: Darkroom, Photoshop, Affinity, others
- Document: Price, target audience, feature set

**Online Tools:**
- Canva, Pixlr, Photopea, etc.
- Use: Try framing a photo in each
- Document: Time, ease, output quality

**CLI Tools:**
- ImageMagick, GraphicsMagick, others with framing
- Research: How many photographers use CLI?
- Document: Learning curve, batch capability

### Competitive Matrix

| Tool | Price | Batch | EXIF | Presets | Learning | Platform |
|------|-------|-------|------|---------|----------|----------|
| Framer | Free | ✅ | ✅ | ⚠️ | Medium | macOS |
| Photoshop | $55/mo | ❌ | ❌ | ✅ | High | Win/Mac |
| Lightroom | $10/mo | ⚠️ | ✅ | ✅ | Low | Win/Mac |
| Darkroom | $5/mo | ⚠️ | ❌ | ✅ | Very Low | iOS |
| Canva | Free | ✅ | ❌ | ✅ | Low | Web |
| LR Plugin X | $15-50 | ⚠️ | ? | ? | ? | Lightroom |

**Finding:** What's the gap? (Likely: "Good batch + EXIF + local + cheap" is unique to Framer)

---

## Phase 4: Analytics Setup (Week 1)

### Before Launch

Set up metrics NOW so we can measure:
- How many people download?
- How long do they use it?
- What features do they use?
- When do they churn?

**Implementation:**
1. Install Posthog or Mixpanel SDK in FramerApp
2. Track key events:
   - App launch
   - First photo import
   - First export
   - Preset save
   - Batch export (3+ photos)
   - Feature usage (layer types)

3. Set up dashboard:
   - Daily signups
   - DAU/WAU/MAU
   - Conversion funnel: launch → import → export
   - Retention curve (Day 1, 3, 7, 30)
   - Feature usage breakdown

**Privacy:** Make analytics opt-in, transparent

---

## Phase 5: YouTube Validation (Weeks 2-4)

### Why YouTube?

If photographers discover tools via YouTube, we need to test:
- Do tutorials get views?
- Do YouTube viewers download the app?
- What topics resonate?

### Video 1: "Batch Frame 100 Photos in 30 Seconds"

**Duration:** 8 minutes
**Hook:** "Stop spending 30 minutes in Photoshop"

**Outline:**
1. Problem: Show photographer opening Photoshop → adding border → exporting (takes 30 sec per photo)
2. Solution: Show Framer → drag 100 photos → click export → done (30 sec total)
3. How it works: Presets, EXIF captions, batch processing
4. Call-to-action: GitHub link, feedback request

**Distribution:**
- Post on YouTube (new "Framer" channel)
- Share on r/photography + r/Lightroom
- Tweet it to photography communities
- Email friends

**Metrics:**
- Views (target: 1,000+)
- Click-through to GitHub (target: 10%)
- Comments (analyze feature requests)
- Signups (track from video)

### Video 2: "EXIF Captions: Auto-Label Your Photos"

**Why make this?** Interviews might reveal photographers love auto-captions.

**Duration:** 6 minutes
**Hook:** "Your camera already stores all this info"

**Outline:**
1. Problem: Photographers manually type camera settings as captions
2. Solution: Framer auto-extracts EXIF (camera, lens, ISO, f-stop, shutter)
3. Features: Template system, date formatting, fonts
4. Example: Batch 50 photos, all captioned in seconds

---

## Success Criteria & Signals

### Interview Signals (Positive)

✅ **Product-market fit indicators:**
1. Photographers say "I hate [current tool], Framer fixes that"
2. >60% say they'd use Framer
3. >50% interested in beta testing
4. Multiple unsolicited feature requests (same features)
5. >$10/month pricing doesn't scare people

❌ **Pivot indicators:**
1. Nobody currently frames photos
2. <30% would use Framer
3. Main use case is different than expected (e.g., "I use it for social media headers, not photos")
4. Distribution is the blocker, not features

### Survey Signals (Positive)

✅ **Product-market fit indicators:**
- >40% say they frame photos regularly
- >60% say framing takes >15 min per 10 photos
- >70% interested in Framer
- Top pain point aligns with Framer's value prop
- >$5/month pricing acceptable to 40%+

### YouTube Signals (Positive)

✅ **Distribution validates:**
- >1,000 views on first video (proves topic resonates)
- >5% click-through to GitHub (proves viewers care)
- >20 YouTube comments with requests/feedback
- >5% of views = new signups (conversion validation)

---

## Decision Framework

### After 4 weeks of research, assess:

**Question 1: Do photographers want to frame photos?**
- If YES → Continue
- If NO → Product is pursuing a non-problem; pivot to something else

**Question 2: Do photographers want to batch-frame?**
- If YES → Framer's unique value prop is strong; invest in Lightroom plugin
- If NO → Simplify app for single-photo use; compete with Darkroom

**Question 3: Would photographers pay?**
- If YES (>40% say yes to $5+/month) → Build freemium tier
- If NO → Keep free, pursue B2B revenue instead

**Question 4: Where do photographers discover tools?**
- If Lightroom marketplace is top answer → Build Lightroom plugin first
- If YouTube → Invest in content marketing
- If Reddit/Twitter → Build community strategy

### Possible Outcomes

| Scenario | Next Steps |
|----------|-----------|
| **PMF validated (>60% interest, clear use case)** | Build Lightroom plugin, charge for premium presets |
| **Weak PMF (40-60% interest, use case unclear)** | Pivot to B2B (studios, labs) or Lightroom-only |
| **No PMF (<40% interest)** | Sunset gracefully or open-source for community |

---

## Timeline Summary

| Phase | Weeks | Owner | Output |
|-------|-------|-------|--------|
| **User interviews** | 1-3 | Product | 20-30 interviews, insights doc |
| **Survey** | 2-4 | Product | 100+ responses, analysis |
| **Competitive research** | 2 | Product | Competitive matrix + positioning |
| **Analytics setup** | 1 | Engineering | Posthog dashboard, events tracking |
| **YouTube videos** | 2-4 | Marketing | 2-3 videos, traffic metrics |
| **Analysis & decision** | 5 | Product | "Pivot or proceed?" recommendation |

**Total duration:** 5-6 weeks
**Team:** 0.5 Product + 0.25 Engineering + 0.25 Marketing

---

## Research Budget

| Item | Cost | Notes |
|------|------|-------|
| Posthog | Free (tier) | Event tracking, no video |
| Typeform/Airtable | Free | Survey tool |
| YouTube | Free | Video hosting |
| Zoom | Free (45min limit) | Interviews, or schedule/record |
| Time | 80 hours | 0.5 product + 0.25 eng + 0.25 marketing |
| **Total** | **$0-200** | Lean, bootstrapped approach |

---

## Success Criteria

**By April 30, 2026, you'll know:**

1. ✅ What photographers' actual framing workflow is (not assumed)
2. ✅ How many would use Framer (% interested)
3. ✅ What distribution channels matter most
4. ✅ What features are must-have vs. nice-to-have
5. ✅ What price point works
6. ✅ Whether to pivot, scale, or sunset

**This is a 6-week investment to avoid wasting 52 weeks on the wrong product.**

---

## Key Interviews Questions (Deeper Dive)

### For Instagram photographers:
- "How do you prepare photos for Instagram?"
- "Do you edit in Lightroom first?"
- "Do you add captions? How?"
- "How many photos per post? Per week?"
- "What tool would save you the most time?"

### For wedding photographers:
- "Walk me through how you deliver photos to clients"
- "Do you add watermarks? Captions? Branding?"
- "How many photos per wedding?"
- "How long does post-processing take?"
- "Would you pay for a tool that cut that in half?"

### For print/portfolio photographers:
- "How do you display your work (web, print, physical portfolio)?"
- "Do you frame prints? How?"
- "Do you sell prints? What does your fulfillment look like?"
- "Would batch processing be valuable for you?"

---

## Template: Interview Debrief

After each interview, fill out 1-page summary:

```
Interview #[X] - [Photographer Name]
Date: [Date]
Duration: [30 min]

Background:
- Type: Instagram / Wedding / Print / Other
- Photo volume: [X] photos/month
- Current tool: [Lightroom/Photoshop/Other]
- Pain point: [Quote their words]

Would they use Framer?
- Interest level: [1-5]
- Why/why not: [Quote]
- Price acceptable: $[X]/month
- Feature requests: [List]

Key insight:
[1-2 sentence takeaway]

Action:
- Beta tester? [Yes/No]
- Follow-up? [Yes/No, date]
```

---

**Document Version:** 1.0
**Created:** March 2026
**Timeline:** 6 weeks (March 15 - April 30)
**Success Metric:** 20+ interviews + 100+ survey responses + PMF decision
