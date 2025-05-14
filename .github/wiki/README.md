# Ingestor System Wiki Configuration

This directory contains configuration files for the GitHub wiki synchronization process. The GitHub Actions workflow automatically syncs content from the docs/ directory to the project's GitHub wiki.

## Configuration Files

- **page-mapping.yml**: Maps source Markdown files to wiki page names
- **sidebar.yml**: Defines the sidebar navigation structure
- **footer.md**: Template for the footer added to each wiki page

## How It Works

1. The `wiki-sync.yml` GitHub Actions workflow runs when documentation files are changed
2. The workflow clones the wiki repository
3. It processes each source file according to the mapping in `page-mapping.yml`
4. The content is copied to the wiki with the footer appended
5. The sidebar navigation is generated from `sidebar.yml`
6. All changes are committed and pushed to the wiki repository

## Adding a New Wiki Page

1. Create a new Markdown file in the appropriate location in the docs/ directory
2. Add an entry to `page-mapping.yml` mapping the source file to a wiki page name
3. Update `sidebar.yml` to include the new page in the navigation
4. Commit and push your changes
5. The workflow will automatically update the wiki

## Structure

### page-mapping.yml

```yaml
mapping:
  "SOURCE_FILE_PATH": "WIKI_PAGE_NAME"
  "README.md": "Home"
  "docs/example.md": "Example-Page"
```

### sidebar.yml

```yaml
sidebar:
  - title: Home
    page: Home
  - title: Section Title
    children:
      - title: Page Title
        page: Page-Name
```

### footer.md

The footer template supports these placeholders:
- `{{LAST_UPDATED}}`: Replaced with the current date/time
- `{{SOURCE_FILE}}`: Replaced with the source file path
- `{{SOURCE_URL}}`: Replaced with the URL to the source file on GitHub

## Manual Trigger

You can manually trigger the wiki sync workflow from the Actions tab in GitHub:

1. Go to the Actions tab
2. Select "Wiki Synchronization"
3. Click "Run workflow"
4. Options:
   - Force update all wiki pages
   - Specify specific files to update
   - Enable/disable link verification

## Troubleshooting

If the wiki synchronization fails:
1. Check the workflow run logs for errors
2. Verify that all referenced files exist
3. Check for syntax errors in the configuration files
4. Ensure all internal links in documentation are correct