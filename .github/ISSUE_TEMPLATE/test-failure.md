---
title: "Test Failure: {{ env.TEST_GROUP }} Tests (Node {{ env.NODE_VERSION }})"
labels: bug,test-failure,needs-triage
assignees: "{{ env.DEFAULT_ASSIGNEE }}"
---

# Test Failure Report

## Summary

The {{ env.TEST_GROUP }} tests have failed on Node.js v{{ env.NODE_VERSION }} in the CI workflow.

## Build Information

- **Commit:** [`{{ env.COMMIT_SHA }}`]({{ env.WORKFLOW_URL }})
- **Test Group:** `{{ env.TEST_GROUP }}`
- **Node.js Version:** `{{ env.NODE_VERSION }}`
- **Workflow Run:** [View on GitHub]({{ env.WORKFLOW_URL }})

## Failure Details

See the [workflow logs]({{ env.WORKFLOW_URL }}) for detailed test output.

## Possible Causes

- Test assertions failing
- Timeout issues
- Environment-specific problems
- Race conditions in asynchronous tests
- Missing dependencies or environment variables

## Next Steps

1. [ ] Review the test logs
2. [ ] Reproduce the issue locally with `npm run test:{{ env.TEST_GROUP }}`
3. [ ] Fix the failing tests
4. [ ] Create a pull request with the fixes
5. [ ] Verify the tests pass in CI

---

_This issue was automatically created by the CI system._