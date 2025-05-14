# Branch Protection Rules

This document outlines the recommended branch protection rules for the Ingestor System repository.

## Configuration Guide

To configure these rules, go to:
1. Repository Settings
2. Branches
3. Branch protection rules
4. Add rule

## Main Branch Protection

Apply these rules to the `main` branch:

### Rule: Protect main branch

#### Branch name pattern
```
main
```

#### Protect matching branches

- [x] Require a pull request before merging
  - [x] Require approvals (1)
  - [x] Dismiss stale pull request approvals when new commits are pushed
  - [x] Require review from Code Owners
  - [x] Require approval of the most recent reviewable push
  - [ ] Require conversation resolution before merging

- [x] Require status checks to pass before merging
  - [x] Require branches to be up to date before merging
  - Status checks that are required:
    - `lint`
    - `build`
    - `test (unit, 16)`
    - `test (integration, 16)`
    - `analyze-results`

- [x] Require conversation resolution before merging

- [x] Require signed commits

- [x] Include administrators

- [ ] Restrict who can push to matching branches
  - Add specific teams/people who can push to this branch

- [x] Allow force pushes
  - [x] Specify who can force push:
    - Repository administrators only
    
- [ ] Allow deletions

## Develop Branch Protection

Apply these rules to the `develop` branch:

### Rule: Protect develop branch

#### Branch name pattern
```
develop
```

#### Protect matching branches

- [x] Require a pull request before merging
  - [x] Require approvals (1)
  - [x] Dismiss stale pull request approvals when new commits are pushed
  - [x] Require review from Code Owners
  - [ ] Require approval of the most recent reviewable push

- [x] Require status checks to pass before merging
  - [x] Require branches to be up to date before merging
  - Status checks that are required:
    - `lint`
    - `build`
    - `test (unit, 16)`

- [x] Require conversation resolution before merging

- [ ] Require signed commits

- [x] Include administrators

- [ ] Restrict who can push to matching branches

- [x] Allow force pushes
  - [x] Specify who can force push:
    - Repository administrators only
    
- [ ] Allow deletions

## Feature Branches Protection

Apply these rules to all feature branches:

### Rule: Protect feature branches

#### Branch name pattern
```
feature/*
```

#### Protect matching branches

- [ ] Require a pull request before merging

- [x] Require status checks to pass before merging
  - [ ] Require branches to be up to date before merging
  - Status checks that are required:
    - `lint`
    - `build`

- [ ] Require conversation resolution before merging

- [ ] Require signed commits

- [ ] Include administrators

- [ ] Restrict who can push to matching branches

- [x] Allow force pushes
  
- [ ] Allow deletions

## Implementation Steps

1. Go to the repository settings (must be an admin)
2. Navigate to "Branches" in the left sidebar
3. Click "Add rule" under "Branch protection rules"
4. Copy the settings from above for each branch pattern
5. Click "Create" or "Save changes"

## Additional Security Recommendations

1. **Require two-factor authentication** for all contributors
2. **Set up code scanning alerts** using GitHub CodeQL
3. **Configure Dependabot alerts** for security vulnerabilities
4. **Set up secret scanning** to prevent credentials leaking
5. **Regular security audits** of the repository permissions

## Workflow Recommendations

1. **Create feature branches** from `develop`
2. **Merge feature branches** into `develop` via pull requests
3. **Create release branches** from `develop` when ready to release
4. **Merge release branches** into `main` when fully tested
5. **Tag releases** on the `main` branch following semantic versioning