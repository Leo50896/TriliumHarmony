# Brand assets and attribution

The launcher icon in this project is derived from the official **Trilium Notes** logo.

## Source

- Repository: `https://github.com/TriliumNext/Trilium`
- File: `apps/client/src/assets/icon.svg`
- Commit used: `985f393e5fc79e80c3aca8a6e19b30ef9f23e088`
- Official site also serves the same SVG as its header logo: `https://triliumnotes.org`

## Files

| File | Purpose |
| --- | --- |
| `trilium-official.svg` | Original SVG downloaded from the official repository |
| `trilium-official-transparent-1024.png` | SVG rendered at 1024×1024, transparent background |
| `trilium-light-1024.png` | Official mark on an off-white background |
| `trilium-dark-1024.png` | Official mark on the app's deep-navy background; used for the HarmonyOS launcher icon and in-app `LogoMark` |

The SVG was rendered at 1024×1024 with Microsoft Edge headless using a transparent page background. The dark launcher variant adds only the app background; the leaf artwork itself is unmodified.

The in-app `LogoMark` component references `$r('app.media.app_icon')` and applies a rounded clip, so the launcher icon, splash icon, login page and drawer header share the same underlying artwork.

## Trademark / license note

The Trilium repository is licensed under **AGPL-3.0**. The name and logo are project branding of TriliumNext and its contributors. This repository is a client UI prototype; if you redistribute it publicly or commercially, verify that your use of the Trilium name/logo complies with the upstream license and trademark guidance, and keep this attribution with the assets.
