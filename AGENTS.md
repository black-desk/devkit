# Agent instructions

- Keep documentation synchronized with substantive code, script, directory, or
  workflow changes in the same commit.
- Keep package inventories, versions, dependencies and build steps in recipes
  and manifests. Explain non-obvious implementation choices beside the code.
  Documentation should cover shared policies, user configuration, operational
  workflows and unresolved findings rather than duplicate recipe contents.
- Keep useful reproductions, ruled-out approaches and validation limits for
  unresolved findings. Once resolved, keep the design reason beside the affected
  implementation and remove superseded experiment logs.
- Do not commit package archives, generated repodata, build directories, or tool
  caches.
- The seed is defined by `seed-packages.tsv`; update that manifest deliberately
  when changing the seed.
- For commits produced with LLM assistance, include this trailer in the commit
  message:

  ```text
  Assisted-by: LLM
  ```
