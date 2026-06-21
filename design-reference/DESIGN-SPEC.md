# TaskTap Mobile — Design Spec (from claude.ai/design "TaskTap Design System")

Source of truth for the Flutter UI. Translate faithfully to Flutter widgets; apply ui-ux-pro-max rules (≥44pt touch targets, 4.5:1 contrast, 150–300ms motion, safe areas, reduced-motion) as the "improve" layer. Italian UI copy.

## Tokens
- **Brand:** Y `#FFF10E`, YDark `#E6D900`, YSoft `rgba(255,241,14,0.2)`
- **Ink:** DARK `#363636`, CHARCOAL `#292929`, FG2 `rgb(112,112,112)`, MUTED `rgb(144,143,143)`, DIS `rgb(180,180,180)`, INV `rgb(242,242,242)`, WHITE `#fff`
- **Surfaces:** BG1 `rgb(250,250,250)`, BG2 `rgb(247,247,247)`, BG3 `rgb(242,242,242)`, BG4 `rgb(237,237,237)`
- **Borders:** BL `rgb(242,242,242)`, BM `rgb(227,227,227)`, BS `rgb(217,217,217)`, DIV `rgb(212,212,212)`
- **Semantic:** AMBER `rgb(255,178,0)`, GREEN `#4caf50`, BLUE `#2563eb`, CYAN `#06AED5`, RED `#ff0000`, REDSOFT `rgb(255,209,209)`
- **Shadow:** SH `0 3px 5.5px rgba(0,0,0,0.10)`; SH_INSET `inset 0 2px 4px rgba(0,0,0,0.10)`
- **Fonts:** FD = Sora (display/titles/KPI), FB = Manrope (body/labels), FA = Inter (fallback/system)

## Status pill colors (Italian)
Aperto bg`rgb(220,232,255)`/fg`#1d4ed8` · In corso bg AMBER/fg`#000` · In pausa bg`rgb(232,232,232)`/fg`#555` · In attesa bg`rgb(220,240,255)`/fg`#06AED5` · Completato bg`rgb(218,242,224)`/fg`#1e7a3a` · Chiuso bg`rgb(232,232,232)`/fg`#363636` · Annullato bg`rgb(255,220,220)`/fg`#a00` · Bozza bg`rgb(245,245,245)`/fg`#666` · Inviata bg`rgb(220,232,255)`/fg`#1d4ed8` · Pagata bg`rgb(218,242,224)`/fg`#1e7a3a` · Scaduta bg`rgb(255,220,220)`/fg`#a00` · Sospeso bg`rgb(255,220,220)`/fg`#a00` · Attivo bg`rgb(218,242,224)`/fg`#1e7a3a`

## Components (393pt design width; scale to device)
- **BottomNav** — floating pill, white bg, 23px radius, 0.5px BL border, SH shadow, margin 19px, bottom 18. 5 tabs: Dashboard(home)/Ticket/Timbra(clock)/Calendario/Altro(more). Active tab: yellow bg, 19px radius, shows icon(18, DARK)+Sora 600/12 label; inactive: icon only (DIS). 200ms transition.
- **ScreenHeader** — 8/19/12 padding; optional back chevron (18); Sora 700/18 title (ellipsis) + optional Manrope 12 MUTED sub; trailing actions.
- **HeaderIconBtn** — 38×38 circle, BG3 bg (or glass on dark), icon 17 DARK; optional red dot badge.
- **Card** — BG1 bg, 14px radius, default padding 16. **GlassCard** (on dark hero): white-translucent gradient, 0.5px white border, SH_INSET, 14px radius.
- **Btn** — variants: primary(Y bg/DARK fg/SH), secondary(BG3/MUTED), dark(DARK/INV/SH), ghost(transparent/DARK), danger(REDSOFT/`#c00`). Manrope 700. Sizes: lg(14/24 pad,16,r20,icon18), md(11/20,14,r18,icon16), sm(6/14,10,r10,icon12). Optional leading icon; full-width option.
- **Badge** — rounded 9px, Manrope 500, 10px (sm 9px), pad 3/9 (sm 2/7). **Chip** — white/DARK or DARK/white(active), 1px border, 5px radius, Manrope 500/11, pad 5/10.
- **StatusPill** — Badge driven by the status-color map above.
- **ListRow** — 12/19 padding, gap 12, bottom 1px BL divider; leading slot; Manrope 600/14 title + Manrope 12 MUTED sub (both ellipsis); meta slot (right); trailing chevron(16 DIS) when tappable.
- **Avatar** — initials circle, default 36, color cycle [Y,#A8DADC,#FFE66D,#06AED5,#F4A261,#FFB200], DARK text, Manrope 700, fontSize size*0.36.
- **KeyVal** — horizontal: Manrope 700/10 MUTED uppercase label (letter-spacing .3) + Manrope 13 DARK value (right, ellipsis), 10px vertical pad, bottom 1px BL divider. Vertical variant: label above value(14).
- **SectionTitle** — Sora 700/18 DARK, pad 20/19/10, optional right action.
- **SearchBar** — BG3 bg, 12px radius, pad 10/14, search icon(16 MUTED) + Manrope 14 input, margin 0 19 12.
- **FAB** — 56 circle, Y bg, big shadow `0 8px 20px rgba(0,0,0,0.18)`, plus icon(24 DARK), bottom-right 19, above nav.
- **Toggle** — 38×22, Y(on)/BM(off) track, 16 white knob, 200ms.
- **Tabs** — horizontal scroll, Manrope 700/12, active DARK + 2px Y underline (inactive MUTED), 12/14 pad; optional count pill.
- **EmptyState** — 60 circle BG3 + icon(26 DIS), Sora 700/16 title, Manrope 13 MUTED body (max 280), optional action; centered, 60/30 pad.
- **Hero** (dashboard) — dark radial/linear gradient with 0.45 black overlay, bottom radius 30, minHeight ~430; "Bentornato" (Manrope 500/16 white) + user name (Sora 700/26 YELLOW); top-right glass bell(badge)+user icons; holds glass cards.
- **ActiveJobCard** (glass) — status badge, Sora 700/18 white title, Manrope 11 client; right: HH:MM:SS timer as separate 40×38 translucent tiles (Manrope 18) + small yellow "Apri attività" btn.
- **StatsGrid** — 2×2, dividers DIV; Manrope 12 MUTED label (pre-line) + Manrope 500/36 DARK value.
- **QuickAction** — 50 yellow circle + icon(20) + Manrope 700/10 centered label.
- **Stepper** (rapportino form) — numbered circles (22) Y(done/current)/BS, check when done, Sora 600/10 labels, 2px connector lines Y/BS.
- **Signature pad** — dashed 1.5px BS border, 10px radius, ~90 tall, signature icon + "Tocca per firmare"; filled state shows the captured stroke + "Firmato il …".

## Notes for Flutter
- Sora + Manrope already via google_fonts (M1). Add Inter as system fallback.
- Replace the M1 placeholder AppColors/AppTextStyles/widgets with this exact token set + component set.
- Keep one icon family (Lucide-equivalent: lucide_icons or a vector set) — no emoji.
- Respect safe areas (notch, home indicator) and ≥44pt touch targets even where the 393pt design draws smaller hit areas.
