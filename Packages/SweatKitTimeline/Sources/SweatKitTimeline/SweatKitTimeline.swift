/// The two custom components of the activity detail screen: the timeline and
/// the stats panel. Both float over the map in Liquid Glass.
///
/// - `ActivityTimeline` draws the elevation profile with one overlay series,
///   scrubs, zooms, selects a range and marks laps.
/// - `StatsPanel` shows the values at the cursor.
///
/// Both take data that is already prepared. Nothing here decodes a file,
/// computes a metric, detects a stop, chooses a zone colour or reads storage.
/// The spec's "Activity detail and flyover" and "Design" sections are the
/// contract.
///
/// The scrub position is a sample index held in a `Binding<Double>`, the same
/// shape `SweatKitFlyover`'s `FlyoverMap` takes, so one binding drives the
/// map, the timeline and the caller's stats together.
public enum SweatKitTimeline {}
