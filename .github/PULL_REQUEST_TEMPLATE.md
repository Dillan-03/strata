## Summary

<!-- What does this change and why? -->

## Linked issue

Closes #

## Implementation details

-

## Testing performed

<!-- Paste real commands and results. Don't claim tests passed unless they ran. -->

- [ ] `swift test` (StrataCore)
- [ ] App unit tests
- [ ] UI tests
- [ ] Manual check:

## Screenshots

<!-- Required for UI changes. Delete this section otherwise. -->

## Security considerations

- [ ] No secrets in code, logs, test output or screenshots
- [ ] Still read-only by default: any write goes through `ConfigWriter`, behind the fixes setting and an approval
- [ ] No new network access

## Documentation changes

-

## CI status

<!-- Link the passing run, or explain why a check doesn't apply. -->

## Reviewer checklist

- [ ] Scoped to the linked issue
- [ ] Claude Code behaviour claims are backed by docs/configuration-resolution.md
- [ ] Error paths handled, not just the happy path
- [ ] No dead code, debug logging or commented-out blocks
