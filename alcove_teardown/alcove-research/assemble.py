#!/usr/bin/env python3
"""Build ALCOVE_TEARDOWN.md: lead report + each child report, with relative links rewritten."""
import re, os, glob
root=os.path.expanduser('~/alcove-research')
out=open(f'{root}/report/ALCOVE_TEARDOWN.md','w')
out.write(open(f'{root}/report/00_lead.md').read())
extra=f'{root}/report/01_reconciled.md'
if os.path.exists(extra): out.write('\n\n'+open(extra).read())
for extra in [f'{root}/report/02_live_v3.md', f'{root}/report/03_v3_summary.md', f'{root}/report/04_v4.md']:
    if os.path.exists(extra): out.write('\n\n'+open(extra).read())
parts=[('A_static','alcove_static_re.md','Part A: static reverse engineering'),
       ('B_runtime','alcove_runtime.md','Part B: runtime inner workings'),
       ('C_media','alcove_media_hud_gestures.md','Part C: media, HUDs and gestures (pass 1)'),
       ('C_media','alcove_media_hud_gestures_v2.md','Part C2: media, HUDs and gestures (pass 2)'),
       ('D_calendar','*.md','Part D: calendar, focus, connectivity, lock screen and settings UI'),
       ('E_hw','*.md','Part E: hardware-dependent features'),
       ('F_gaps','*.md','Part F: gap-closing reverse engineering (v2)'),
       ('G_v3','*.md','Part G: uncovered areas (v3): games, sounds, URL scheme, particles, updater, AppleScript, performance, displays'),
       ('H_v4','alcove_v4/alcove_v4_spotify_cycle.md','Part I: v4 live tests: Spotify explicit badge and cycle-activity swipe thresholds')]
for d,pat,title in parts:
    fs=sorted(glob.glob(f'{root}/children/{d}/{pat}'))
    if pat=='*.md': fs=fs[:1]
    for f in fs:
        txt=open(f).read()
        base=f'children/{d}/'
        def fix(m):
            url=m.group(2)
            if re.match(r'^(https?:|#|/|mailto:)',url): return m.group(0)
            # locate file inside the child's tree
            cand=[p for p in glob.glob(f'{root}/{base}**/'+os.path.basename(url),recursive=True)]
            rel=os.path.relpath(cand[0],root) if cand else base+url
            return f'{m.group(1)}({rel})'
        txt=re.sub(r'(!?\[[^\]]*\])\(([^)\s]+)\)',fix,txt)
        txt=re.sub(r'^(#+)',r'#\1',txt,flags=re.M)  # demote headings one level
        out.write(f'\n\n---\n\n# {title}\n\n_Source: `{base}{os.path.basename(f)}`. Evidence lives in `{base}`._\n\n'+txt)
out.close()
print(os.path.getsize(f'{root}/report/ALCOVE_TEARDOWN.md'))
