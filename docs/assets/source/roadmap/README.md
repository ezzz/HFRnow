# Roadmap diagram sources

- `../../roadmap-milestones.excalidraw` is the editable diagram: open it on <https://excalidraw.com> or in any Excalidraw editor.
- `elements.json` is the same diagram in the compact element format of the Excalidraw MCP that drew it.
- `export.html` and `export.js` are the architecture diagram's exporter (`docs/architecture/source`), with the output renamed. They regenerate `roadmap-milestones.svg` and `roadmap-milestones.excalidraw` with the Virgil font embedded, so GitHub renders the SVG without fetching fonts.

The figures in the boxes (percentages, lot counts) are a snapshot. Live state is on the milestone boards: [#166](https://github.com/ezzz/HFRnow/issues/166) (M1) and [#324](https://github.com/ezzz/HFRnow/issues/324) (M2–M4).

Regenerate (Node + Playwright with Chromium):

```sh
cd docs/assets/source/roadmap
npm pack @excalidraw/utils@0.1.2 && tar -xzf excalidraw-utils-0.1.2.tgz && cp package/dist/excalidraw-utils.min.js .
npm pack @excalidraw/excalidraw@0.18.1 && tar -xzf excalidraw-excalidraw-0.18.1.tgz && cp package/dist/prod/fonts/Virgil/Virgil-Regular.woff2 .
node export.js && mv roadmap-milestones.svg roadmap-milestones.excalidraw ../..
```

Downloaded files are git-ignored.
