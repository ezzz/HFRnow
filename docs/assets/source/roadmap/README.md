# Roadmap diagram sources

- `elements.json` is the **only** source: change the diagram there, then regenerate. Regeneration overwrites `../../roadmap-milestones.excalidraw` and `../../roadmap-milestones.svg`.
- `../../roadmap-milestones.excalidraw` can be opened on <https://excalidraw.com> to look at it. A change made in an editor is lost at the next regeneration, unless it is first carried back into `elements.json`.
- `elements.json` uses the compact element format of the Excalidraw MCP that drew the diagram.
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
