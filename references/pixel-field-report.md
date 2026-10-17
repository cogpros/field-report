# Pixel Field Report

Use this visual variant only when the user requests it or the report is a
review of an existing pixel-style interface. It changes the appearance of a
report copy; the canonical template remains the source of all interaction.

## Build

1. Copy `canonical-template.html` and fill its normal placeholders and review
   sections. Keep the canonical script, section IDs, checkbox IDs, `data-q`
   fields, POST button, and floating-notes behavior.
2. Insert `pixel-style.css` just before the copied report's closing `</style>`.
   Replace `__SILKSCREEN_FONT_BASE64__` with the base64 content of
   `assets/Silkscreen-Regular.ttf`. This embeds the font in the HTML, so the
   report remains a single offline file. Keep `assets/Silkscreen-OFL.txt` with
   the skill when redistributing the font.
3. Use the subject app's actual color tokens and screen shape when the report
   previews that app. The CSS palette is a starting point. Put labels and
   facts outside image pixels; stock art must not imply the appearance or
   condition of an individual real subject.

For a generated report, this Python fragment inserts the bundled CSS and font
without changing the template's JavaScript. Set `skill_dir` to the installed
`field-report` directory and `report_path` to the completed HTML copy:

```python
import base64
from pathlib import Path

style = (skill_dir / "references/pixel-style.css").read_text()
font = base64.b64encode((skill_dir / "assets/Silkscreen-Regular.ttf").read_bytes()).decode("ascii")
style = style.replace("__SILKSCREEN_FONT_BASE64__", font)
html = report_path.read_text()
assert html.count("</style>") == 1
report_path.write_text(html.replace("</style>", style + "\n</style>", 1))
```

Apply it once to a fresh template copy. On later edits, update the report's
Patched timestamp and changelog instead of inserting the CSS again.

## Review surface

- Use Silkscreen across the entire report, including paragraphs, buttons,
  notes, and POST controls. Keep body text readable with adequate size and
  line height; the pixel variant is one visual language throughout.
- Use `.pixel-screen` for a framed phone or app preview, `.pixel-gallery` for
  an image collection, and `.pixel-card` for each labeled item. The supplied
  CSS uses `image-rendering: pixelated` only on the visual assets.
- Make proposed controls visibly different from live controls. If the report
  shows sensor or other changing data, label it with its capture time or as an
  illustration. Do not let a mock control submit a real action.
- Keep the canonical light/dark toggle, focus indicators, POST receipt, and
  feedback inputs usable at narrow widths. Check at a desktop width and a
  phone width; inspect the rendered page, image decoding, and horizontal fit.

The source example for this variant was a Grow Tent phone-dashboard review.
Its artwork and plant details belong to that project, so this public skill
ships only the reusable style and licensed font.
