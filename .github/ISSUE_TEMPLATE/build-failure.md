---
title: "Build Failure: {{ env.BUILD_ID }}"
labels: bug,build-failure,needs-triage
assignees: "{{ env.DEFAULT_ASSIGNEE }}"
---

# Build Failure Report

## Summary

The build process has failed for commit `{{ env.COMMIT_SHA }}`.

## Build Information

- **Build ID:** `{{ env.BUILD_ID }}`
- **Commit:** [`{{ env.COMMIT_SHA }}`]({{ env.WORKFLOW_URL }})
- **Workflow Run:** [View on GitHub]({{ env.WORKFLOW_URL }})

## Failure Details

See the [workflow logs]({{ env.WORKFLOW_URL }}) for the build output and error details.

## Possible Causes

- TypeScript compilation errors
- Missing dependencies
- Configuration issues
- Environment problems

## Next Steps

1. [ ] Review the build logs
2. [ ] Reproduce the issue locally with `npm run build`
3. [ ] Fix the build issues
4. [ ] Create a pull request with the fixes
5. [ ] Verify the build succeeds in CI

---

_This issue was automatically created by the CI system._