# Contributing to Moksha

This is the workflow for any change to the app — your own work, work
from collaborators, AI-assisted edits.

`main` is protected. **Direct pushes to `main` are blocked.** Every
change reaches `main` through a Pull Request that must pass CI.

---

## Branch naming

| Prefix | Use for | Example |
| --- | --- | --- |
| `feature/` | New functionality | `feature/dark-mode` |
| `fix/` | Bug fixes | `fix/kundli-empty-insights` |
| `chore/` | Maintenance, deps, tooling | `chore/bump-firebase-sdk` |
| `experiment/` | Throwaway exploration (often never merged) | `experiment/voice-chat` |
| `hotfix/` | Urgent prod fix that bypasses normal review | `hotfix/payment-crash-on-launch` |

---

## Workflow

### 1. Branch from `main`

```bash
git checkout main
git pull
git checkout -b feature/my-thing
```

### 2. Commit your work to that branch

Small, focused commits. Push when ready:

```bash
git add .
git commit -m "Add feedback button to settings"
git push -u origin feature/my-thing
```

### 3. Open a Pull Request

On GitHub: <https://github.com/sarvesh973/vedastro-ai/pulls> → **New pull request** → base: `main`, compare: `feature/my-thing`.

In the PR description, write:
- **What** changed
- **Why** it changed
- **How to test** (which screens to check, which flows to run)

### 4. CI builds a debug APK for the PR

When you push to a PR branch, the workflow `Build APK + AAB` triggers in **debug mode**:

- Builds an unsigned debug APK (no keystore exposure to PR runs)
- Uploads as artifact `Moksha-PR-<number>-debug-apk`

Download it from the run summary page → sideload on a real device → test the change.

### 5. Merge when ready

If everything works:
- On the PR page → **Merge pull request** → confirm
- This triggers a fresh `main` build with the production keystore → produces the signed AAB you'd ship to Play Store

If something's wrong → push more commits to the same branch (PR auto-updates) or close the PR without merging.

### 6. After merging — clean up the branch

```bash
git checkout main
git pull
git branch -d feature/my-thing      # delete locally
git push origin --delete feature/my-thing   # delete on GitHub
```

GitHub also offers a "Delete branch" button on the merged PR page.

---

## CI behavior summary

| Trigger | What CI builds | Where it goes |
| --- | --- | --- |
| Push to `main` | Signed release AAB + APK + debug symbols | Artifacts of run, retention 30/90 days; AAB → Play Store |
| Open / update PR to `main` | Unsigned debug APK | Artifact named `Moksha-PR-<n>-debug-apk`, retention 14 days |
| Manual `workflow_dispatch` | Treated as push to that branch | — |

---

## Keystore & signing

**Never include the keystore (`vedastro-release.jks`) in any commit.** It's stored as base64 in GitHub Secrets (`KEYSTORE_BASE64`) and only injected during `main`-branch CI runs. PR builds never see it — that's deliberate so PRs from forks or experimental branches can't sign with the production key.

Recovery is possible from GitHub Secrets if needed (see `docs/KEYSTORE_SETUP.md`), but treat the local copy at `C:\Users\user\OneDrive\Desktop\Astro\vedastro-release.jks` as the canonical backup.

---

## Hotfix path

For urgent production breakage where the normal review cycle is too slow:

1. Branch from `main` as `hotfix/<one-line-summary>`
2. Make the minimal possible fix
3. Open a PR labelled `hotfix`
4. CI passes → merge yourself (admin override)
5. New AAB is built on `main`; upload to Play Console as a patch release

Use sparingly. Most "urgent" things can wait 5 minutes for a regular PR.

---

## Common mistakes to avoid

- **Stale branches.** Keep branches short-lived (≤ 1 week). Rebase onto latest `main` if your branch ages.
- **Massive PRs.** One concern per PR. Don't bundle a paywall redesign with a Razorpay fix — if one is buggy you can't ship either.
- **Force-push on shared branches.** Fine on solo work, dangerous if anyone else has pulled.
- **Skipping the PR for "tiny" changes.** Even a one-character typo deserves the PR cycle now that `main` is protected — the cost is 30 seconds, the benefit is auditability.

---

## Questions?

Email `sarry1254@gmail.com` or open an issue.
