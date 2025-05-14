# CI/CD Pipeline Documentation

This document describes the Continuous Integration and Continuous Deployment (CI/CD) pipeline set up for the Ingestor System project.

## Overview

The CI/CD pipeline automates testing, linting, building, and releasing of the Ingestor System. It is implemented using GitHub Actions and triggered automatically on code changes.

## Workflow Triggers

The pipeline is triggered on:

- **Push to the main branch**: Runs full pipeline including linting, testing, and building
- **Pull requests to the main branch**: Runs linting and testing to validate changes
- **Tag pushes with `v*` pattern**: Runs full pipeline and creates a GitHub release

## Pipeline Jobs

### 1. Code Quality (Lint)

This job ensures code quality by:

- Installing ShellCheck
- Running `./scripts/lint.sh` to check all shell scripts
- Reporting any code style or potential issues

### 2. Testing

This job validates functionality by:

- Setting up the Node.js environment
- Installing all required system dependencies
- Installing testing dependencies (BATS and libraries)
- Running the full test suite with `./scripts/run_tests.sh`

### 3. Build

This job verifies the build process by:

- Setting up the Node.js environment
- Installing dependencies
- Creating the environment structure
- Verifying that the build can run with `./src/ingestor --version`
- Archiving build artifacts for the release job

### 4. Release

This job creates official releases when triggered by a version tag:

- Downloads build artifacts from the build job
- Creates a tarball package of the release
- Generates release notes
- Creates a GitHub release with the tarball attached
- Sets prerelease flag based on version suffix (alpha/beta/rc)

## Code Analysis

A separate workflow runs more in-depth code analysis:

- ShellCheck for shell script analysis with detailed output
- CodeQL Analysis for JavaScript code security scanning
- Scheduled to run weekly in addition to on push/PR events

## Local Development

When developing locally, you can use these scripts to ensure your code passes the same checks run in CI:

```bash
# Run linting
./scripts/lint.sh

# Run tests
./scripts/run_tests.sh

# Create a new release (updates version and creates git tag)
./scripts/release.sh --type patch --message "Bug fixes and improvements"
```

## Creating Releases

To create a new release:

1. Run the release script:
   ```bash
   ./scripts/release.sh --type minor --message "Added new feature X"
   ```
   
   This script will:
   - Update the version in package.json
   - Run tests to validate the release
   - Commit the version change
   - Create a git tag with the version and message

2. Push the changes and tag:
   ```bash
   git push origin main
   git push origin v1.2.0  # Replace with actual version
   ```

3. The CI/CD pipeline will automatically:
   - Run all tests and checks
   - Build the project
   - Create a GitHub release
   - Attach release artifacts

## CI/CD Pipeline Configuration

The pipeline configuration is stored in YAML files in the `.github/workflows/` directory:

- `ci-cd.yml`: Main pipeline for testing, building, and releasing
- `code-analysis.yml`: Code quality and security scanning

## Troubleshooting

If the CI/CD pipeline fails:

1. Check the GitHub Actions logs for specific error messages
2. Run the failing checks locally to reproduce the issue
3. Fix the issue and push the changes

Common failure points:
- Linting errors: Run `./scripts/lint.sh --fix` to automatically fix some issues
- Test failures: Run `./scripts/run_tests.sh` with the `--verbose` flag for detailed output
- Build issues: Check dependencies and environment setup