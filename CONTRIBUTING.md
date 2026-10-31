# Contributing to NotchUtils

Thanks for helping out! Suggestions are as valuable as code, so please don't feel you need to write any.

## Suggest something

- **Ideas and questions:** start a thread in [Discussions](https://github.com/rupajsen/NotchUtils/discussions/categories/ideas).
- **Bugs:** open an [issue](https://github.com/rupajsen/NotchUtils/issues/new/choose). Your Mac model, macOS version and steps to reproduce help a lot.

## Change the code

1. For anything big, open a discussion first so nobody's work goes to waste.
2. Fork the repo and create a branch from `main`.
3. Build and run your change:

   ```bash
   ./scripts/build.sh
   open dist/NotchUtils.app
   ```

   Quit any running copy first. `--open <tab>` starts the app pinned open on a tab (`media`, `timer`, `shelf`, `system` or `credits`), which is handy when working on the interface:

   ```bash
   dist/NotchUtils.app/Contents/MacOS/NotchUtils --open timer
   ```

4. Open a pull request saying what changed and why. Add a screenshot or recording for anything visible.

### Guidelines

- **Stay light.** The app runs all day, so avoid work while the notch is closed. Check CPU in Activity Monitor before and after anything that animates.
- **Stay native.** Prefer system frameworks, and discuss any new dependency first.
- **Don't take focus.** The panel must never take keyboard focus from the app you're working in.
- **Protect privacy.** No analytics, and no new network requests without a clear reason.
- **Match the code around you.** New source files start with the same two-line SPDX and copyright header.

### Screenshots

The images in `docs/images` come from the app's own views with made-up data. If you change the interface, regenerate them rather than adding real screenshots that show your own music or files:

```bash
./scripts/render-demo.sh
```

## Licensing

By contributing, you agree that your contribution is licensed under the project's [MIT License](LICENSE).

## Be kind

Please be respectful and assume good intent. Everyone here is trying to make something nice.
