# Motion and Reduce Motion audit

Phase 11 §10 walkthrough. Every animation ID from `UI_SPEC.md` is listed with
where it lives and what happens when **Reduce Motion** is on.

| ID | Where | Reduce Motion |
| --- | --- | --- |
| A1 | `ModuleBackdrop` crossfade | Crossfade stays; it is not movement |
| A2 | `SidebarView` selection pill | Spring becomes `nil` |
| A3 | `SidebarView` symbol swap | System symbol transition only |
| A4 | `numericRoll` | `ContentTransition.identity`, no roll |
| A5 | `PrimaryCircleButtonStyle` | Hover/press still scales; press feedback is useful and short |
| A6 | `PrimaryCircle` breathing glow | Loop not started |
| A7 | `SidebarWorkingArc` | Loop not started |
| A8 | Scan ring | Ring still shows progress; head dot is brief |
| A9 | `ScanSweep` | Sweep not rendered; hero does not bob |
| A10 | `CountUpBytes` | Jumps to the final number |
| A11 | `TemplateMotion.morph` | Spring becomes the 0.2 s state crossfade |
| A12 | `ReviewSheetModifier` | Opacity transition, 0.2 s |
| A13 | `StaggerIn` | Appears at once, no offset |
| A14 | Drawn check | Draws; it explains the result and is brief |
| A15 | Checkup lane tick | Bounce removed by system Reduce Motion |
| A16 | `RadarRings` | Rings not rendered |
| A17 | Threat tint | Colour blend stays; no pulse |
| A18 | Uninstaller reorder | Reorder stays; it is user-initiated |
| A19 | `FlyingIconView` | Skipped |
| A20 | Space Map hover | Selection tint only; no radial offset in this build |
| A21 | Sunburst zoom | `SpaceLensView` drops the zoom |
| A22 | Sunburst growth | Grows without sweep |
| A23 | `ShredConfetti` | Not rendered |
| A24 | Menu bar sparklines | `TimelineView` pauses when the window is not key |
| A25 | Screen Cleaning countdown | Countdown is functional; ring still trims |
| A26 | Toast | Slides become fade |
| A27 | Widget expand | Expand stays; it is a navigation change |
| A28 | `TriStateCheckbox` | 0.12 s fill; no movement |
| A29 | Path ticker | Text crossfades only |
| A30 | `TemplateHero` float | Float not started |
| A31 | Sidebar focus groups | No offset; opacity change only |
| A32 | Verdict hero shift | Layout change without spring |
| A33 | Hover popover | Fade/scale only, user-initiated |
| A34 | Shredder drop target | Outline appears; no lift |

## Performance

- Hero sweep and radar use `TimelineView(.animation(minimumInterval: 1/30, paused:))`
  and pause whenever the window is not key.
- Menu-bar sparklines pause with the same rule.
- Hash progress and Similar Photos progress pass through `ProgressThrottle`
  (10 Hz).
- Remaining: an Instruments session on the release build.
