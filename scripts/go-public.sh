#!/usr/bin/env bash
# Makes the repository public and turns on the protections a public repo should have.
# Before running: if the ByteStash API key used during development is still active, revoke it.
# GitHub keeps the diffs of merged pull requests #4 and #5, which contain it, and they become public too.
set -euo pipefail
R=js-surya/bytecache

gh repo edit "$R" --visibility public --accept-visibility-change-consequences

# Secret scanning blocks pushes that contain keys; Dependabot reports vulnerable dependencies.
gh api -X PATCH "repos/$R" --input - <<'JSON'
{"security_and_analysis": {"secret_scanning": {"status": "enabled"},
                           "secret_scanning_push_protection": {"status": "enabled"}}}
JSON
gh api -X PUT "repos/$R/vulnerability-alerts" >/dev/null
# SECURITY.md sends reporters here.
gh api -X PUT "repos/$R/private-vulnerability-reporting" >/dev/null

# Workflows from first-time outside contributors wait for approval (they could burn build minutes).
gh api -X PUT "repos/$R/actions/permissions/fork-pr-contributor-approval" -f approval_policy=first_time_contributors >/dev/null

# main and develop: no force pushes or deletion, changes only through pull requests;
# main also needs the build to pass. The owner can bypass in an emergency.
for branch in main develop; do
    checks=""
    [ "$branch" = main ] && checks=',{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"required_status_checks":[{"context":"build"}]}}'
    gh api -X POST "repos/$R/rulesets" --input - >/dev/null <<JSON
{"name": "Protect $branch", "target": "branch", "enforcement": "active",
 "conditions": {"ref_name": {"include": ["refs/heads/$branch"], "exclude": []}},
 "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}],
 "rules": [{"type": "deletion"}, {"type": "non_fast_forward"},
           {"type": "pull_request", "parameters": {"required_approving_review_count": 0, "dismiss_stale_reviews_on_push": false,
            "require_code_owner_review": false, "require_last_push_approval": false, "required_review_thread_resolution": false}}$checks]}
JSON
done

gh repo edit "$R" --homepage "https://github.com/$R/releases"
echo "Public: https://github.com/$R"
