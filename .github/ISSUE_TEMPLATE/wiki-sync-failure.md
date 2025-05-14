---
name: Wiki Synchronization Failure
about: Created automatically when the wiki synchronization workflow fails
title: 'Wiki Synchronization Failed'
labels: bug, documentation
assignees: ''
---

The wiki synchronization workflow failed. This issue has been created automatically to track the problem.

## Failure Information

- **Commit**: [COMMIT_SHA]
- **Workflow Run**: [WORKFLOW_URL]
- **Time of Failure**: [FAILURE_DATE]

## Common Causes

- **Markdown Syntax Errors**: Check for invalid Markdown syntax in the affected files
- **Broken Internal Links**: Verify that all internal document links point to existing files
- **Configuration Issues**: Check the `.github/wiki/page-mapping.yml` and `.github/wiki/sidebar.yml` files
- **Wiki Repository Access Issues**: Ensure the GitHub Actions workflow has proper permissions

## Steps to Resolve

1. Review the workflow logs to identify the specific error
2. Fix the issue in the affected files
3. If necessary, manually trigger the wiki synchronization with the "Force update all wiki pages" option
4. Verify the wiki content is properly updated

## Additional Debug Information

[ADD_ANY_ADDITIONAL_DEBUG_INFO_HERE]

---

/cc @project-maintainers