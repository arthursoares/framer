# GitHub Pages rebuild

The published site is `https://arthursoares.github.io/framer/`, served from
`main/docs`. Arthur requested a rebuild with current screenshots, images,
and descriptions. Keep GitHub Pages and the dependency-free static stack.

## Plan before implementation

1. Replace the CLI-only page and obsolete Homebrew/short-flag examples with
   an accurate v2.2.0 product page. Distinguish the downloadable unsigned arm64
   CLI from macOS/iOS source builds.
2. Use a darkroom editorial direction: warm readable type, dark surfaces,
   large real app imagery, and clear install choices.
3. Create two new demo photographs, then render the gallery with the real
   released Framer CLI. Publish the matching YAML recipes and image provenance.
4. Capture current macOS/iOS UI screenshots using the generated demo photo.
   Do not fabricate interface screenshots or effects.
5. Build one responsive page with workflow descriptions, an accessible
   original/finish comparison, example gallery, and working install/copy links.
6. Verify markup, scripts, links, asset sizes, small-screen layout, and the
   published result. Review the completed diff, merge the authorized site update,
   and wait for GitHub Pages deployment before handing over the URL.

No app code, release version, dependency, or hosting-provider change is needed.
