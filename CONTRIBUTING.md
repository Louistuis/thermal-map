# Contributing to Thermal Map

Thanks for wanting to help. Anyone with a Mac is welcome.

- **Add your Mac model:** follow [docs/ADD-A-MAC.md](docs/ADD-A-MAC.md). It covers everything from dumping your sensors to fitting and proving the heat model, and how to do it with Claude Code (Thermal Map was built with Claude Opus 5.5 at high effort).
- **Bugs and ideas:** open an issue with your Mac model (`sysctl -n hw.model`), macOS version and what you saw.
- **Pull requests:** one Mac or one change per pull request. Include renders made with `--render` and, for layouts, the `--score` numbers before and after fitting.

Build with `./build.sh` (Command Line Tools only, no Xcode project). Please never put test windows on screen in scripts; use the headless modes.
