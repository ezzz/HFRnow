# Architecture diagram sources

- `../architecture.excalidraw` is the editable diagram: open it on <https://excalidraw.com> or in any Excalidraw editor.
- `elements.json` is the same diagram in the compact element format used by the Excalidraw MCP that drew it.
- `export.html` / `export.js` regenerate `architecture.svg` and `architecture.excalidraw` from `elements.json` with the official `@excalidraw/utils` library, with the Virgil font embedded so GitHub renders it without fetching fonts.

Regenerate (Node + Playwright with Chromium):

```sh
cd docs/architecture/source
npm pack @excalidraw/utils@0.1.2 && tar -xzf excalidraw-utils-0.1.2.tgz && cp package/dist/excalidraw-utils.min.js .
npm pack @excalidraw/excalidraw@0.18.1 && tar -xzf excalidraw-excalidraw-0.18.1.tgz && cp package/dist/prod/fonts/Virgil/Virgil-Regular.woff2 .
node export.js && mv architecture.svg architecture.excalidraw ..
```

Downloaded files are git-ignored. When editing the diagram by hand on excalidraw.com instead, export it as SVG with "Embed scene" enabled and replace both files.
