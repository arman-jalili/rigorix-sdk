## What this changes

<!-- One paragraph. If it fixes an issue, write "Closes #N". -->

## Why

<!-- The failure it prevents or the capability it adds. A guard needs the failure
     it was shown to refuse. -->

## Validation

<!-- The command you ran and what it printed. `bash .ci/local-ci.sh` prints a
     step count and a verdict line; copy that line rather than a typed number. -->

```
LOCAL CI: …
```

## Checklist

- [ ] I have signed the [CLA](docs/CLA.md) (the bot records it on the pull request)
- [ ] Generated files were regenerated, not edited (`go generate`, `bundle_schemas.py`, `bundle-schemas.mjs`)
- [ ] A guard change comes with a seed that shows it refusing
- [ ] `schemas/` changes carry a delta note under `docs/`
- [ ] No secret, token, or credential is in the diff or the commit messages
