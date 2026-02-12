# S0 SwiftUI Preview Policy

## Rule
When possible, each migrated SwiftUI view should provide previews with mock data.

## Minimum variants
1. Happy path
2. Loading
3. Empty
4. Error

## Mocking principles
- Use deterministic fixtures.
- Avoid runtime network or side effects.
- Prefer protocol-based injected services for preview data.

## Current implementation status
- Initial mock previews added for row-level views:
  - `TopicRowView`
  - `MPRowView`
- Next: list-level previews using mock services and injected view models.
