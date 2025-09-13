# GitHub Actions Workflows

## Homebrew Formula Validation

This repository includes a GitHub Actions workflow that automatically validates the Homebrew formula for r128x-cli.

### Workflow: `homebrew-formula-check.yml`

**Schedule:** Every Monday at 00:00 GMT+0 (weekly)

**Purpose:** 
- Ensures the `r128x.rb` Homebrew formula is up-to-date with the latest release
- Validates formula syntax using Homebrew's audit tools
- Tests actual compilation and installation of the CLI tool
- Verifies the installed binary works correctly

**Triggers:**
- 🕐 **Scheduled**: Weekly on Monday at midnight GMT
- 🔄 **Manual**: Can be triggered manually via GitHub Actions UI
- 📝 **Push**: Runs when `r128x.rb` or the workflow file is modified

**Validation Steps:**
1. **Tag Verification**: Checks if formula tag matches latest GitHub release
2. **Syntax Validation**: Runs `brew audit --strict --online` on the formula
3. **Build Test**: Attempts to build and install r128x-cli from source
4. **Binary Test**: Verifies the installed binary responds correctly
5. **Architecture Check**: Ensures binary matches the runner architecture

**Automatic Issue Creation:**
If the formula is outdated (tag doesn't match latest release), the workflow automatically creates a GitHub issue with:
- Details about the version mismatch
- Step-by-step instructions for updating the formula
- Links to the failed workflow run

### Benefits

- **Proactive Maintenance**: Catches formula issues before users encounter them
- **Release Sync**: Ensures Homebrew formula stays current with releases
- **Quality Assurance**: Validates that the formula actually works on clean systems
- **Automated Alerts**: Creates actionable issues when updates are needed

### Local Testing

To test the formula locally before pushing:

```bash
# Validate syntax
brew audit --strict r128x.rb

# Test installation
brew install --build-from-source r128x.rb

# Test the binary
r128x-cli
```

### Maintenance

The workflow is designed to be self-maintaining, but you may need to:
- Update the macOS runner version if Apple releases new requirements
- Adjust the cron schedule if weekly checks are too frequent/infrequent
- Modify validation steps if the formula structure changes significantly