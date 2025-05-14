---
title: "CI Workflow Failure: {{ env.BUILD_ID }}"
labels: bug,ci-failure,needs-triage
assignees: "{{ env.DEFAULT_ASSIGNEE }}"
---

# CI Workflow Failure Report

## Summary

The CI workflow for commit `{{ env.COMMIT_SHA }}` on branch `{{ env.BRANCH_NAME }}` has failed.

## Build Information

- **Build ID:** `{{ env.BUILD_ID }}`
- **Commit:** [`{{ env.COMMIT_SHA }}`]({{ env.WORKFLOW_URL }})
- **Branch:** `{{ env.BRANCH_NAME }}`
- **Workflow Run:** [View on GitHub]({{ env.WORKFLOW_URL }})

## Failure Details

| Component | Status | Details |
|-----------|--------|---------|
| Linting & Style | {{ env.LINT_STATUS == 'success' && '✅ Passed' || '❌ Failed' }} | |
| Build | {{ env.BUILD_STATUS == 'success' && '✅ Passed' || '❌ Failed' }} | |
| Tests | {{ env.TEST_STATUS == 'success' && '✅ Passed' || '❌ Failed' }} | |

### Test Failures

- Unit Tests: {{ env.UNIT_FAILURES }} failures
- Integration Tests: {{ env.INTEGRATION_FAILURES }} failures
- Performance Tests: {{ env.PERFORMANCE_FAILURES }} failures

### Code Coverage

Current coverage: {{ env.COVERAGE }}% (Threshold: 80%)

## Next Steps

1. [ ] Review the [workflow logs]({{ env.WORKFLOW_URL }})
2. [ ] Fix identified issues
3. [ ] Create a pull request with the fixes
4. [ ] Ensure all tests pass on the fix branch before merging

---

_This issue was automatically created by the CI system._