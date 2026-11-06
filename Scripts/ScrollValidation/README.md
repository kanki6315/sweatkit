# Activity scrolling regression

`python3 Scripts/ScrollValidation/prepare.py /tmp/sweatkit-scroll-harness`
creates a disposable app using the production feed and a synthetic 110-activity
library. Generate its project with XcodeGen, then run the SweatKit scheme's tests
on a simulator leased through Simlock (see CLAUDE.md).

Before presenting the feed, the harness checks first-page loading, pagination,
retention of all loaded IDs across refresh, the final page, and resetting the
window when filters change. The UI test scrolls the list, opens a visible activity,
and verifies that the same row remains visible after returning. Its screenshot
is attached to the test result.

These short synthetic walks verify behavior, not real-device frame rate or
network-dependent map loading. Use a populated device library for profiling.
