# Website image credits and recipes

The September 2026 website uses newly generated demo photography and actual
Framer v2.2.0 output. The photographs do not document real locations or camera
captures, and no camera metadata is claimed for them.

## Demo photography

Two source photographs were created with OpenAI image generation for this site:

- **Coast**: a photorealistic rocky sea cliff with dark stratified stone, a slate
  sea, storm clouds and a break of light; muted charcoal, slate, and olive tones;
  a wide 3:2 composition with no people, text, logo, or border.
- **Architecture**: a photorealistic modernist ochre mineral-plaster facade with
  recessed windows and concrete planes; warm late sunlight and cool geometric
  shadows; a wide 3:2 composition with no people, signs, text, logo, or border.

These are summaries of the generation directions. The original generated files
were 1536 × 1024 PNG images. The website publishes resized JPEG originals and
Framer-rendered finishes, with the corresponding YAML configurations:

| Image | Treatment | Recipe |
| --- | --- | --- |
| [coast-original.jpg](coast-original.jpg) | Resize only | [YAML](recipes/coast-original.yaml) |
| [coast-film.jpg](coast-film.jpg) | B&W Film, Tri-X grain, rough border | [YAML](recipes/coast-film.yaml) |
| [coast-color.jpg](coast-color.jpg) | Distant Past shader | [YAML](recipes/coast-color.yaml) |
| [architecture-original.jpg](architecture-original.jpg) | Resize only | [YAML](recipes/architecture-original.yaml) |
| [architecture-halftone.jpg](architecture-halftone.jpg) | Color halftone shader | [YAML](recipes/architecture-halftone.yaml) |
| [architecture-ascii.jpg](architecture-ascii.jpg) | Color ASCII shader | [YAML](recipes/architecture-ascii.yaml) |

Each finish was rendered with the Framer v2.2.0 CLI and then encoded as a
quality-85 JPEG for the web. The comparison images use matching dimensions.
The recipes reproduce the processing settings; applying them to the published
JPEG originals may yield small differences from the original PNG renders.

To apply a recipe to your own photo, download its YAML file and run:

```sh
./framer -i photo.jpg -f finished.jpg --config coast-film.yaml
```

## Application screenshots

- [app-macos.jpg](app-macos.jpg): actual macOS app, v2.2.0 source build, with the
  coast photograph and expanded Film preset controls.
- [app-ios.png](app-ios.png): actual iOS app, v2.2.0 source build in the simulator,
  with the coast photograph, comparison controls, and layers.

Application interfaces were captured directly, not generated or reconstructed.
The screenshots demonstrate app presets; the separate gallery demonstrates the
published CLI recipes. These are not intended to show identical preset settings.

The favicon is the repository's existing Framer app icon. Website fonts are
Atkinson Hyperlegible Next, distributed under the SIL Open Font License; see
[the font license](../fonts/OFL.txt).
