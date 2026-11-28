#!/bin/bash

# Style-lint YAML with yamllint against .yamllint.yml at the repo root. The
# rules there track conventions this repo already enforces elsewhere
# (.editorconfig's 120 columns and its exemptions, ratchet's one-space pin
# comments), so the two never disagree. Syntax validity is a separate check:
# lint_config.sh parses the same files with yq.

set -euo pipefail

# shellcheck source=bin/lint_lib.sh
. "$(dirname "$(readlink -f "$0")")/lint_lib.sh"

lint_require yamllint
lint_collect '*.yml' '*.yaml' -- "$@"

[ "${#files[@]}" -eq 0 ] && exit 0

# --strict: yamllint exits 0 on warnings by default, which would let most of
# its rules fail silently. Everything it still warns about here is deliberate.
yamllint --strict -c "$BASE_DIR/.yamllint.yml" "${files[@]}"
