## Summary

Refs #57. The 401 from the Central Portal was **not (only) a revoked token**:
`actions/setup-java` writes `${env.MAVEN_CENTRAL_USERNAME}` and
`${env.MAVEN_CENTRAL_TOKEN}` into `~/.m2/settings.xml`, and the Maven deploy step
exported only `MAVEN_GPG_PASSPHRASE`. Maven therefore sent **empty credentials**,
and the Portal answered `401 Invalid request` — which looks exactly like a bad
token.

## Change

Export both secrets on the deploy step:

```yaml
      - name: Deploy with sources, javadoc and signatures
        run: mvn -B -Prelease deploy
        env:
          MAVEN_CENTRAL_USERNAME: ${{ secrets.MAVEN_CENTRAL_USERNAME }}
          MAVEN_CENTRAL_TOKEN: ${{ secrets.MAVEN_CENTRAL_TOKEN }}
          MAVEN_GPG_PASSPHRASE: ${{ secrets.MAVEN_GPG_PASSPHRASE }}
```

Also corrects the missing-secrets message from `dev.rigorix` to `eu.rigorix`
(the actual groupId/namespace).

## Why a dispatch, not another tag replay

The `v0.9.0` tag points at commit `63575ec`, which predates this workflow fix;
`gh run rerun` would use the old workflow again. After this merges, run the
workflow on `main`:

```bash
gh workflow run publish.yml --ref main
```

`workflow_dispatch` skips the npm/PyPI publish steps (`if: github.event_name ==
'push'`) and the smoke job, but the Maven job has no such guard, so it deploys
the 0.9.0 POM with the exported credentials.

## Verification

```
YAML parse                                             ✅
Maven deploy step now exports both secrets             ✅
namespace message corrected (eu.rigorix)               ✅
```

The Central credential itself was refreshed in the Actions secrets in the prior
step; this fixes the path that delivers it to Maven. #57 closes only when
`maven-metadata.xml` reports `release: 0.9.0` and `.../0.9.0/` returns 200.
