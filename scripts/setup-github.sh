#!/bin/sh
# One-time GitHub setup: private repo, Actions secrets, push main (scaffold) + v1 branch, open the PR.
# Run from the repo root: scripts/setup-github.sh
set -e
REPO=patelheet30/scene-stash
KEY=~/.appstoreconnect/private_keys/AuthKey_SM5T2V6U96.p8

gh repo create "$REPO" --private --description "Scene Stash — a UIKit movie & TV tracker for iOS"
git remote add origin "git@github.com:$REPO.git" 2>/dev/null || true

printf "Paste your TMDB API Read Access Token (input hidden): "
stty -echo; read -r TMDB; stty echo; echo
gh secret set TMDB_TOKEN -R "$REPO" --body "$TMDB"
gh secret set ASC_KEY_P8 -R "$REPO" < "$KEY"
gh secret set ASC_KEY_ID -R "$REPO" --body SM5T2V6U96
gh secret set ASC_ISSUER_ID -R "$REPO" --body 728f39f5-8f5b-4d5e-a229-79a215403bae

# main gets only the scaffold (first TestFlight build proves signing works); the app lands via PR.
git push -u origin main
git push -u origin v1
gh pr create -R "$REPO" --base main --head v1 --title "Scene Stash v1" --body "The full app: Tonight, Discover, Stash, detail, onboarding, iCloud store. Merging uploads to TestFlight."
