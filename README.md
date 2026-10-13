# Hacker News

A light, native iOS reader for [Hacker News](https://news.ycombinator.com), built with SwiftUI. It reads directly from the official [HN Firebase API](https://github.com/HackerNews/API), plus the site's own discussion pages for comments — there is **no backend**; everything, including notifications, runs on-device.

## Features

- **Paginated top stories** — explicit prev/next page controls (30 stories per page), not infinite scroll.
- **Opens links in the default browser** — tapping a title opens the article in Safari. Ask/Show HN posts without an external link fall back to their HN discussion page.
- **Visited tracking** — stories you've opened are remembered and rendered slightly dimmed.
- **Threshold notifications** — get a local notification when a top story crosses a points threshold you set.
  - Never notifies about a story you've already opened.
  - Never notifies about the same story twice.
- **Hide the numbers** — optionally hide points and/or comment counts, so stories are judged on their titles.
- **Popular-story highlight** — stories at or above a points threshold you set get a small orange flame beside their rank, even when points are hidden.
- **Collapsible comments** — tap a comment to collapse it. Only its *replies* hide; the comment itself stays visible.

## Requirements

- Xcode 26.5+
- iOS 26.5+ (simulator or device)

## Build & run

```sh
cd ios
open HackerNews.xcodeproj
```

Then select an iPhone simulator and run (`⌘R`).

From the command line:

```sh
cd ios
xcodebuild -project HackerNews.xcodeproj -scheme HackerNews \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Notifications

Notifications are powered entirely on-device by a `BGAppRefreshTask` — no push server or Apple Push certificates are required. The trade-off is that **iOS decides when the background refresh actually runs**, so real notifications can be delayed and won't fire on demand in the Simulator.

To enable and test:

1. Open **Settings** (gear icon, top-right) and turn on **Notify on popular stories**, then grant the permission prompt.
2. Set a **points threshold** (default 300; lower it to e.g. 50 to test easily).
3. Tap **Check for popular stories now** — this runs the exact same scan/filter/notify logic the background task uses, so you can verify notifications immediately instead of waiting for iOS to schedule a refresh.

## Architecture

SwiftUI with `@Observable` view models and `MainActor` isolation. State is persisted in `UserDefaults` (kept free of SwiftUI) so the background task can read the same visited/settings data.

```
ios/HackerNews/
├── HackerNewsApp.swift       App entry; registers the background task
├── Models.swift              HNItem — decoded from the HN API
├── HNClient.swift            Async API client (concurrent, order-preserving fetch)
├── CommentPageParser.swift   Reads a comment thread out of an HN discussion page
├── Stores.swift              VisitedStore, AppSettings, NotifiedStore (UserDefaults)
├── NotificationManager.swift Permission, BGAppRefreshTask, threshold rule
├── StoriesViewModel.swift    Page-based pagination state
├── StoriesView.swift         Story list, row, pagination controls
├── CommentsViewModel.swift   Paged comment tree (CommentNode) + collapse flattening
├── CommentsView.swift        Threaded, collapsible comments
├── SettingsView.swift        List display, highlight, notifications
├── HTMLText.swift            Minimal HN-comment HTML → plain text
├── RelativeTime.swift        "2h ago" formatting
└── Info.plist                Background modes + permitted task identifier
```

Comments are read from the story's page on news.ycombinator.com rather than the API: the page carries the whole thread, ranked as the site ranks it, in one request — where the API needs one request per comment, a reply level at a time. The API walk remains as a fallback if the page can't be fetched or parsed. The thread shows 10 top-level comments at a time, with **Load more comments** revealing the next 10. Reopening a thread shows everything through the page you were reading, so your scroll position and collapsed comments come back as you left them.

## Tests

`HackerNewsUITests/HackerNewsUITests.swift` contains a UI test that opens the first story's comments and collapses the top comment (capturing before/after screenshots):

```sh
cd ios
xcodebuild test -project HackerNews.xcodeproj -scheme HackerNews \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:HackerNewsUITests/HackerNewsUITests/testCommentsAndCollapse
```
