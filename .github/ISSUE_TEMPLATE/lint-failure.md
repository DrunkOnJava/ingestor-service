---
title: "Lint Failure: Code Style Issues"
labels: bug,lint-failure,needs-triage
assignees: "{{ env.DEFAULT_ASSIGNEE }}"
---

# Lint Failure Report

## Summary

Code style and linting checks have failed for commit `{{ env.COMMIT_SHA }}`.

## Build Information

- **Commit:** [`{{ env.COMMIT_SHA }}`]({{ env.WORKFLOW_URL }})
- **Workflow Run:** [View on GitHub]({{ env.WORKFLOW_URL }})

## Failure Details

| Check | Status |
|-------|--------|
| ESLint | {{ env.ESLINT_STATUS == 'success' && '✅ Passed' || '❌ Failed' }} |
| Prettier | {{ env.PRETTIER_STATUS == 'success' && '✅ Passed' || '❌ Failed' }} |
| TypeScript | {{ env.TS_STATUS == 'success' && '✅ Passed' || '❌ Failed' }} |

See the [workflow logs]({{ env.WORKFLOW_URL }}) for detailed lint output.

## Next Steps

1. [ ] Review the lint errors in the workflow logs
2. [ ] Run the appropriate check locally:
   - ESLint: `npm run lint`
   - Prettier: `npx prettier --check "src/**/*.{ts,tsx,js,jsx,json}"`
   - TypeScript: `npm run typecheck`
3. [ ] Fix the code style issues
4. [ ] Create a pull request with the fixes
5. [ ] Verify the lint checks pass in CI

## Automatic Fixing

Many lint issues can be fixed automatically:

```bash
# Fix ESLint issues
npm run lint -- --fix

# Fix Prettier issues
npx prettier --write "src/**/*.{ts,tsx,js,jsx,json}"
```

---

_This issue was automatically created by the CI system._