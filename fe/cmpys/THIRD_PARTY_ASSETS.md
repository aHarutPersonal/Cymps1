# Third-party image assets

## Mentor Lab voices

- `assets/images/voices/isaac_newton.jpg` — Godfrey Kneller, *Portrait of
  Isaac Newton (1642–1727)*, 1689, head-shot crop. Wikimedia Commons,
  public-domain artwork and reproduction:
  <https://commons.wikimedia.org/wiki/File:Portrait_of_Sir_Isaac_Newton,_1689_(head_shot_crop).jpg>
- `assets/images/voices/seneca.jpg` — Peter Paul Rubens, *Bust-length portrait
  of Seneca*. Wikimedia Commons, public-domain artwork and CC0 digital
  reproduction:
  <https://commons.wikimedia.org/wiki/File:Peter_Paul_Rubens_-_Brustbild_des_Philosophen_Seneca_-_178_-_Staatliche_Kunsthalle_Karlsruhe.jpg>
- `assets/images/voices/warren_buffett.jpg` — Warren Buffett at the 2015
  SelectUSA Investment Summit, USA International Trade Administration.
  Wikimedia Commons, United States federal-government public domain:
  <https://commons.wikimedia.org/wiki/File:Warren_Buffett_at_the_2015_SelectUSA_Investment_Summit_(cropped).jpg>

The Mentor Lab quotation sources are shown on their cards. Seneca uses Richard
M. Gummere's 1917 public-domain translation of *Moral Letters to Lucilius*,
Letter 11. Newton is quoted from his 5 February 1676 letter to Robert Hooke,
with the original spelling of “sholders” modernized to “shoulders.” Buffett is
quoted from Columbia Business School's 2015 *Fast Forward: Warren Buffett ’51*.

# Generated motion and image assets (CMPYS v3 design)

These AI-generated clips and images come from the CMPYS v3 Claude Design
project (`CMPYS v3.html`, `v3/*.jsx`), where they were hosted under
`https://d8j0ntlcm91z4.cloudfront.net/user_3KXWTb8owla1yYMTiPxwfUYFIjg/`.
They were downloaded on 29 October 2026 and re-encoded for the app. The app
never streams them from that host. Videos: 720×1280 H.264, 24 fps, about
2.4 Mbps, audio removed; the two landscape sources were centre-cropped to
9:16. Images: WebP, quality 78, longest side 1280 px. No clip shows a real
person.

| Bundled file | Source file | Used for |
|---|---|---|
| `assets/videos/splash.mp4` | `hf_20261027_194749_b9389155-0649-4ba4-892e-5d671bce67c3.mp4` | Splash background |
| `assets/videos/mentor_lab.mp4` | `hf_20261027_195258_6b8e8133-b734-49c5-a915-b0fc21ba7760.mp4` | Mentor lab background |
| `assets/videos/mentor_buffett.mp4` | `hf_20261027_201341_62d664d9-f935-4f3c-8013-265138841a25.mp4` | Warren Buffett preview and mentor screen backdrop (a study scene, not footage of him) |
| `assets/videos/week_unlock.mp4` | `hf_20261027_201242_8c4530e2-f83e-4043-8fb6-ee516175ddd5.mp4` | “Week unlocked” moment |
| `assets/videos/listening.mp4` | `hf_20261027_201425_638df0c7-6473-4c2c-9d6d-d83d89dc03f4.mp4` | Listening player background |
| `assets/videos/celebrate_tutorial.mp4` | `hf_20261027_202054_76bb16e5-f348-4ed4-b064-57d6e777f750.mp4` | Tutorial-complete celebration |
| `assets/videos/celebrate_habits.mp4` | `hf_20261027_200101_08a50f6f-e8ce-4750-a53e-855da5214b94.mp4` | Habits-complete celebration |
| `assets/images/generated/mental_model_farm_a.webp` | `hf_20261027_195901_f68cbe22-cdd3-431a-a4fa-5a132708583e.png` | Mission mental-model card (farm models only) |
| `assets/images/generated/mental_model_farm_b.webp` | `hf_20261027_195849_f040f06c-7001-432f-8b1f-a2adebc3b6e1.png` | Mission mental-model card (farm models only) |

# Third-party fonts

## Geist Sans

- `assets/fonts/geist/Geist-Regular.ttf`, `Geist-Medium.ttf`,
  `Geist-SemiBold.ttf` and `Geist-Bold.ttf` (weights 400/500/600/700) — the
  static Geist Sans TrueType files from the `geist` npm package, version
  1.3.1 (<https://www.npmjs.com/package/geist>,
  <https://github.com/vercel/geist-font>, <https://vercel.com/font>).
- License: SIL Open Font License, Version 1.1. The full text ships beside the
  fonts in `assets/fonts/geist/OFL.txt`; it is also available at
  <https://openfontlicense.org>.
- Copyright (c) 2023 Vercel, in collaboration with basement.studio.

Instrument Serif and Literata are loaded through the `google_fonts` package
(SIL OFL 1.1) and are not bundled.
