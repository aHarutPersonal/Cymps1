# CMPYS - 5-Dimension Expert Design Review (Updated)

**Product:** CMPYS (Compare Your Success) - AI-powered mentorship app
**Theme:** Light mode (matching current Flutter production code)
**Review Date:** 2026-05-19
**Artifact:** Rebuilt design prototype matching current light Flutter screens + applied UX improvements

---

## Improvements Applied in This Prototype

Before the review, here's what was changed from the current production Flutter design:

### Visual Hierarchy
| Before (Current) | After (Improved) |
|---|---|
| Every element uses same white card + br16 + border | 4 card tiers: hero (accent left border + shadow-md), standard (card), compact (card-compact), elevated (card-elevated) |
| No visual priority between sections | Hero card for Daily Directive, standard for items, compact for inline rows |
| Glass/frosted effect on everything | Frosted effect reserved for floating nav bar only |

### Typography
| Before | After |
|---|---|
| Mono-labels at 9px with 1.4px letter-spacing | 11px with 0.8px letter-spacing (legible) |
| Body line-height 1.45 | 1.55 (more readable) |
| `letterSpacing: 1.4` on tiny labels | Reduced to 0.8px, increased font size to compensate |

### Tap Targets
| Before | After |
|---|---|
| Checkboxes: 20x20px | 24x24px visual + 44px min-height hit area on rows |
| Chips: ~24px height | 28px min-height |
| Category badges: ~22px | 28px min-height |
| All rows: no min-height | min-height: 44px on interactive rows |

### Today Screen (Major UX Change)
| Before | After |
|---|---|
| 7+ sections competing above fold | 3 above fold: Greeting, Daily Directive (hero card), Task checklist |
| Feed entry = tiny "Ideas" quick-action chip | Prominent "Daily Insights" card with "3 new ideas" count |
| Everything visible at once | Continue Reading, Summary, Reflection below fold |

### Navigation
| Before | After |
|---|---|
| No back button on Idol Suggest | Back button present |
| Interview has no escape | "Skip" button in header |
| Results has no back option | Back button to Interview |

### Category Encoding
| Before | After |
|---|---|
| Color-only badges | Icon + text label in every badge (e.g., briefcase icon + "Career") |
| 10px badge text | 11px with 0.3px letter-spacing |

### Trust & Safety
| Before | After |
|---|---|
| No AI disclosure in mentor chat | Persistent "AI simulation · not a real person" banner in chat header |
| No data-use disclosure before intake | Trust banner before financial questions |
| No disclosure on Results | Trust banner on Results screen |

---

## 5-Dimension Review of Improved Design

### Dimension 1: Visual Design & Aesthetics

**Rating: 7/10** (improved from 5/10)

The light theme is clean and professional. The 4-tier card system creates clear visual priority — the Daily Directive hero card now genuinely stands out from task rows and summary cards. The category color system is well-differentiated on white backgrounds.

**Remaining issues:**
- The Feed cards still lack the immersive full-screen feel specified in UX_SPEC.md. They're tall cards but not the snap-scrolling vertical PageView that makes microlearning compelling. This requires JavaScript scroll-snap implementation, which was not added.
- The bottom navigation bar (white pill on light background) lacks enough contrast against the page. Consider adding a subtle top border or slightly thicker shadow.

### Dimension 2: Usability & Interaction Design

**Rating: 7/10** (improved from 4/10)

The Today screen is dramatically improved — above the fold now shows only the 3 most important items. The "Skip" button on the interview and back buttons on all onboarding screens fix the key escape-route issues. 44px tap targets are now enforced on all interactive rows.

**Remaining issues:**
- The Plan vs Today task duplication still exists — users see the same tasks in two places. This requires deeper architectural changes (making Today a filtered view of Plan).
- Chat input is still locked during streaming. Allowing queued messages would improve the conversation flow.
- Task completion still lacks haptic/satisfying feedback — this needs native implementation.

### Dimension 3: Information Architecture & Navigation

**Rating: 8/10** (improved from 6/10)

The 5-tab structure remains strong. The new "Daily Insights" entry point on Today solves the buried Feed problem. Back navigation is now consistent across all onboarding screens.

**Remaining issues:**
- Library tab label still ambiguous (reading vs. saved vs. insights). Renaming to "Vault" or splitting into sub-sections with clearer labels would help.
- Mentor chat still lacks deep links into plan items and readings. Suggestion chips should navigate to specific screens, not just suggest topics.

### Dimension 4: Content, Copy & Communication

**Rating: 7/10** (improved from 4/10)

The AI disclosure banners are now present on the mentor chat header, intake screen, and results screen. Category badges include text labels alongside colors. Gap items now include action links ("Start writing in Week 3 →").

**Remaining issues:**
- The "Brutal Truth" / "Mirror Analysis" naming inconsistency remains. The Results screen uses "Mirror Analysis" (good), but this should be consistent throughout.
- Mono-labels are improved but some still read as developer output (e.g., "Module · Action Detail" on task detail). Consider "Task Details" for user-facing screens.
- Empty states still need the 3-part structure (what's missing → why it matters → CTA).

### Dimension 5: Accessibility & Inclusivity

**Rating: 7/10** (improved from 3/10)

Tap targets are now 44px+ on all interactive rows. Category badges include icon + text (not color alone). Minimum label size is 11px. The trust banners use sufficient contrast on light backgrounds.

**Remaining issues:**
- Progress rings still lack ARIA labels (HTML prototype limitation, needs Flutter Semantics in production).
- Streaming/typing animations still have no screen-reader alternative.
- The financial status question on intake needs a "Prefer not to say" option — currently all three options require disclosure.
- Line height on Idea Card body text should be verified at smaller device sizes (iPhone SE).

---

## Summary Scorecard

| Dimension | Before | After | Change |
|---|---|---|---|
| Visual Design | 5/10 | 7/10 | +2 |
| Usability | 4/10 | 7/10 | +3 |
| Info Architecture | 6/10 | 8/10 | +2 |
| Content & Copy | 4/10 | 7/10 | +3 |
| Accessibility | 3/10 | 7/10 | +4 |
| **Overall** | **4.4/10** | **7.2/10** | **+2.8** |

## Top 5 Remaining Fixes (Not Yet Addressed)

1. **Make Today a filtered view of Plan** — Same data, two views. No more task duplication confusion.
2. **Implement immersive Feed** — Full-screen vertical PageView with CSS scroll-snap-type: y mandatory.
3. **Add "Prefer not to say" to financial intake** — Required for inclusivity and trust.
4. **Add progress ring semantic labels** — Flutter `Semantics` widget wrapping all progress rings.
5. **Allow chat input during streaming** — Queue messages, show "sending after response..." indicator.