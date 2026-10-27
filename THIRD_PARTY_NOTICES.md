# Third-party notices

## logicxkit

Copyright 2026 Mike Farr. Apache License, Version 2.0.

MixManifest's read-only Swift Logic ProjectData parser adapts binary field knowledge and selected parsing logic from [logicxkit](https://github.com/phierceweb/logicxkit/tree/75b58fbf597a2ea1296b68323c09c7e3bed84ff6), pinned at commit `75b58fbf597a2ea1296b68323c09c7e3bed84ff6`.

The adaptation implements native Swift bounded reads and a read-only project manifest. It does not include the upstream Python runtime, editing commands, sample sessions, or donor data. Upstream files consulted include `logic/services/insert.py`, `environment.py`, `tracklist.py`, `binding.py`, `levels.py` and plug-in record descriptions.

The upstream [LICENSE](THIRD_PARTY_LICENSES/logicxkit-Apache-2.0.txt) and [NOTICE](THIRD_PARTY_LICENSES/logicxkit-NOTICE.txt) are included verbatim. Changes: native Swift port, stricter format/length validation, explicit partial-support diagnostics, JSON/text manifest export, and macOS UI.

Logic Pro and Apple are trademarks of Apple Inc. MixManifest is not affiliated with or endorsed by Apple.

## License scope of this distribution

`Sources/MixManifestCore/LogicProjectReader.swift` is distributed under Apache-2.0,
with the original attribution and notices retained. Its adaptations include native
Swift bounded reads, explicit unsupported-format diagnostics and provenance.

The remaining directly authored app, manifest, tests and build tooling are covered
by the root MIT license, Copyright 2026 Sungwoon Jeon. No root license replaces
the upstream Apache-2.0 terms or Apple's rights in its products and frameworks.
