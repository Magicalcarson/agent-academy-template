---
name: accessibility-review
description: "Standalone whole-screen / cross-artifact accessibility (a11y) audit - keyboard and focus, screen-reader semantics, color and contrast, forms, mobile and zoom, and Thai/English legibility - producing WCAG-referenced, severity-ranked findings. Owns the independent a11y review lane; component-level correctness stays with react-patterns."
---

# Accessibility Review Skill

Use this skill when reviewing whole frontend screens, forms, dashboards, reports, mobile workflows, color palettes, typography, or generated UI as one independent accessibility pass.

## Principle

Accessible UI is not optional polish. It makes daily operations faster, safer, and less error-prone. Reference a concrete standard (WCAG 2.2 AA as the default bar) so a finding is evidence against a criterion, not a matter of taste.

## Scope and handoffs

This skill owns the **independent, whole-screen a11y audit lane** — the cross-cutting review no single component owns. It does not replace and should hand off to:

- `react-patterns` — React 19 / Radix component correctness and hooks-level semantics (the mechanics of an accessible component).
- `frontend-design` — aesthetic direction and typography intent (choose the type; a11y checks it stays legible/contrasting).
- `theme-factory` — palette/token definitions (a11y verifies the chosen tokens meet contrast, it does not pick them).

When a finding is really a component-mechanics or palette-token issue, name the owner in the fix column and route it there.

## Checklist

1. Keyboard and focus
   - all controls reachable
   - visible focus states
   - no keyboard traps

2. Screen reader semantics
   - labels for inputs
   - meaningful buttons
   - headings in order
   - table headers and captions where needed

3. Color and contrast
   - text contrast adequate (WCAG 1.4.3: 4.5:1 body, 3:1 large text/UI)
   - status not conveyed by color alone (WCAG 1.4.1)
   - error/warning/success clear in Thai and English

4. Forms
   - errors next to fields
   - required fields clear
   - helpful examples
   - no placeholder-only labels

5. Mobile and zoom
   - works at 200% zoom (WCAG 1.4.4)
   - touch targets large enough (WCAG 2.5.8: ~24px min)
   - no horizontal scrolling for core tasks (WCAG 1.4.10)

## Apartment-specific focus

- Staff may use phone while walking/at rooms.
- Meter reading forms must be legible outdoors.
- Financial numbers must be easy to compare.
- Thai text must not be cramped.

## Output format

Each issue cites the WCAG criterion (or "heuristic" if none applies), the concrete evidence, and a severity.

```markdown
# Accessibility Review

## Overall status
- (screen/artifact, standard bar = WCAG 2.2 AA)

## Issues
| Issue | WCAG / standard | Evidence (where seen) | Impact | Severity (blocker/serious/minor) | Fix (owner if handoff) |
|---|---|---|---|---|---|

## Quick wins
- 

## Tests to run
- 
```
