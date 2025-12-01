---
name: writing-tests
description: "STOP. About to write code? Write the test FIRST. Use when user says: 'add', 'implement', 'create', 'fix', 'build', 'write' + any feature/function. Also: touching tested code, fixing bugs, tests fail, coverage drops. RED→GREEN→REFACTOR is mandatory."
---

# Test-Driven Development

## Core Discipline

**No production code without a failing test first.**

This is non-negotiable. Every feature, bug fix, or behavior change follows the RED → GREEN → REFACTOR cycle.

### The Cycle

1. **RED**: Write a single minimal test demonstrating desired behavior. Run it. **Watch it fail.**
2. **GREEN**: Write the simplest code to make the test pass. Nothing more.
3. **REFACTOR**: Clean up while tests stay green. Improve names, remove duplication.
4. Repeat for the next behavior.

### Critical Verification

- You MUST see the test fail before writing production code
- Tests passing immediately means you're verifying existing behavior, not driving new development
- If you wrote production code first, **delete it** and start with the test

### Why This Matters

- A test you didn't see fail might not test what you think
- Writing tests first designs better APIs (you experience them as a user first)
- Small cycles catch bugs immediately, not after building on broken foundations

## Project-Specific Patterns

Read `/TESTING.md` completely before writing any test. It covers:

- Core Module Pattern (extract business logic from GenServers)
- What to test vs. what to skip
- Testing behavior, not implementation
- Coverage targets (85%+ overall, 95%+ for Core modules)
- Mocking strategy with Mox
- LiveView testing approach
- coveralls-ignore rules and required justification format

## Workflow by Scenario

### New Feature

1. Read `/TESTING.md`
2. Design the API by writing a test for the first behavior (RED)
3. Run the test, verify it fails for the expected reason
4. Implement minimal code to pass (GREEN)
5. Refactor if needed, keeping tests green
6. Repeat steps 2-5 for each behavior until feature complete
7. Extract to Core module if logic belongs outside GenServer
8. Add Mox expectations for external calls
9. Ensure tests use `async: true` or document why not
10. Run `mix check` to verify coverage

### Bug Fix

1. Read `/TESTING.md`
2. Write a test that reproduces the bug (RED)—this documents the defect
3. Run test, verify it fails for the right reason (the bug)
4. Fix the bug with minimal code (GREEN)
5. Identify and test related edge cases (more RED→GREEN cycles)
6. Refactor if needed

### Refactoring

1. Verify existing tests pass—they define correct behavior
2. Make changes in small steps, running tests after each
3. Maintain or improve coverage
4. No new coveralls-ignore without documented reason and approval

## Commands

```bash
mix test                           # Full suite
mix test test/path_test.exs        # Single file
mix test test/path_test.exs:42     # Single test at line
mix test --failed                  # Re-run failures
PRINT_LOGS=true mix test           # With log output
mix coveralls                      # Coverage report
mix coveralls.html                 # HTML coverage report
```

## Quality Indicators

**Good tests:**
- Have descriptive names stating the behavior being verified
- Test one behavior each
- Demonstrate intended API usage
- Use real code over mocks where possible

**Warning signs:**
- Tests pass immediately when written (didn't see RED)
- Heavy mocking obscuring actual behavior
- Vague names like `test_it_works`
- Testing implementation details instead of behavior
