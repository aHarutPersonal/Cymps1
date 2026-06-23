# CMPYS UX Specification

**Owner:** UX/IA Agent  
**Status:** Canonical mobile IA and trust/safety spec  
**Last updated:** 2026-05-13

## Canonical IA

Primary first-run path:

`Profile Setup -> Agentic Intake -> Idol Pick -> Interview -> Results -> Plan -> Today`

Main tabs:

- **Today:** daily focus, streak, continue reading, reflection, weekly summary.
- **Plan:** 12-week path, weeks, task details, lessons, resources.
- **Mentor:** chat/studio with quick links into current work.
- **Library:** reading, insights, saved resources.
- **Profile:** account, settings, notifications, appearance, support.

Discover/Ideas remains available as a secondary route from Today or Library, not a primary tab.

## Screen Requirements

### Agentic Intake

- Collect only age, current life context, and interests.
- Explain how sensitive life-context data is used.
- Warn users not to enter passwords, account numbers, or private documents.
- Disclose that mentors are AI simulations based on public information.

### Results

- Name the comparison as the Mirror analysis.
- Name the blueprint as a Strategic blueprint or Mentor verdict.
- Clarify that the 12-week plan is where execution happens.
- Include trust copy that historical/resource claims are AI-assisted and should be verified for major decisions.
- Always offer a concrete next action into Plan or Today.

### Today

- Be the default daily landing surface after activation.
- Show daily focus, daily instructions, streak, weekly summary, continue reading, and reflection.
- Reflection saves to Notes and attaches to the current plan item when available.

### Mentor

- Mentor chat must include links into current daily focus, plan, and reading.
- Mentor copy should support action, not become a generic chat surface.

### Library

- Reading resources, insights, and saved materials belong here.
- Items connected to a plan should show the relevant week when available.

## Accessibility Rules

- All tap targets should be at least 44x44 logical pixels.
- Progress rings and icon-only controls need semantic labels or adjacent text.
- Do not rely on color alone for categories or completion.
- Long-form lessons must support comfortable line height and resumable reading.
- Typewriter/thinking effects should not hide essential state; static text must communicate progress.

## Trust and Safety Patterns

- Use concise AI simulation disclosure on mentor and results surfaces.
- Show source/confidence affordances where grounded evidence exists.
- The "brutal truth" tone must end with agency: next task, plan, or reflection.
- Sensitive intake fields need data-use copy before submission.
