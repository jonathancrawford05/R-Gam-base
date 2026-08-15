# Published builds

**Generated from `catalog/builds/*.json` by `scripts/catalog.py render`.**
Do not edit; edits are overwritten on the next publish. The JSON records are
written by CI out of the image it just published, so every value here was read
from the installed library rather than asserted by hand.

Pin by digest. To see what is in an image without trusting this file:

```bash
docker run --rm ghcr.io/jonathancrawford05/r-gam-base@<digest> \
  cat /opt/oracle-manifest.json
```

Narrative about how builds came to be is in [HISTORY.md](HISTORY.md), which is
commentary and is not machine-checked.

| build | tag | digest | R | CRAN snapshot | mgcv | mboost | built (UTC) | source |
|---|---|---|---|---|---|---|---|---|
| 1 | `r4.6.1-cran2026-08-01-b1` | `sha256:a77a61cf231933e17ec037ee0a63450067f66200a29ebc1cddbed14b8625ce8e` | 4.6.1 | 2026-08-01 | 1.9.4 | — | 2026-08-09T21:23:56Z | backfilled |
| 2 | `r4.6.1-cran2026-08-01-b2` | `sha256:8853bf2b600f6ce0fcae8e29d0a78e4b95ed3603dacb4f5cafa49e7c29606b7c` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-11T00:15:02Z | backfilled |
| 3 | `r4.6.1-cran2026-08-01-b3` | `sha256:9ea27ff8103aff292ec775e85a1d7ca810f7ea43dcde49d40ab210c13c591aaa` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-14T12:28:08Z | backfilled |
| 4 | `r4.6.1-cran2026-08-01-b4` | `sha256:e295b0e23bc4eb8dab806b1e46830dde477e44259b54dcea3a9135538a9ed61c` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-14T12:56:48Z | backfilled |
| 5 | `r4.6.1-cran2026-08-01-b5` | `sha256:f77fd7ae6bfc86154e846632b0dad4e552ecf488d2db86b90074c9f8305c6037` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-14T13:06:31Z | backfilled |
| 6 | `r4.6.1-cran2026-08-01-b6` | `sha256:779c286a13531d3d89e9742b282348dea1f6ce940c66a75d0f78ae41461550be` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-14T18:45:38Z | backfilled |

`source` is `published` when CI wrote the record from the image at publish
time, and `backfilled` when it was reconstructed afterwards from that build's
workflow run. Backfilled records may omit packages that were never recorded.

