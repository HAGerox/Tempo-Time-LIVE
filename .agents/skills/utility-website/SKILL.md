---
name: utility-website
description: Add or update a minimal utility-app product page and catalogue entry, including screenshots and downloads.
---

Find the user's shared apps website before creating a new site. Keep application and website repositories separate.

- Reuse the existing shared Astro product page and app-data entry. Follow that repository's instructions. Avoid building a parallel layout for one app.
- Homepage: apps above the fold, icon, name, neutral platform label and one factual sentence. No screenshots or introductory hero.
- Product page: brief task description, prominent latest download, essential compatibility, two real screenshots and only useful supporting explanation. Each fact once; no compulsory feature grids or repeated navigation.
- Prefer a stable GitHub latest-release asset URL that downloads the installer directly. Verify actual filenames and compatibility rather than guessing them. Do not claim support just because an underlying library supports it.
- Use utility-screenshots when captures need updating. Retain PNG originals; load WebPs with intrinsic dimensions and useful alt text.
- Build and inspect desktop and narrow layouts. Check real download destinations. Keep existing site appearance and approved copy unless the requested change requires otherwise.

If no shared site exists, use a small static Astro site with its official GitHub Pages workflow. Publishing follows the user's authorization; preparing a page does not itself authorize deployment.
