#!/usr/bin/env bash
# Build and publish to GitHub Pages (gh-pages branch). Usage: scripts/deploy.sh
# The site lives at https://<owner>.github.io/<repo>/ so the build uses that base path.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
NAME="${REPO#*/}"
BASE_PATH="/$NAME/" npm run build
rm -rf .deploy && mkdir .deploy && cp -R dist/. .deploy/ && touch .deploy/.nojekyll
cd .deploy && git init -q -b gh-pages && git add -A && git -c user.name="deploy" -c user.email="deploy@local" commit -q -m "Deploy $(date -u +%Y-%m-%dT%H:%MZ)" \
  && git push -q -f "https://github.com/$REPO.git" gh-pages
cd .. && rm -rf .deploy
echo "Published: https://${REPO%%/*}.github.io/$NAME/"
