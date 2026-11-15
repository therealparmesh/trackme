# GPS recording review

Reviewed on 2026-11-15 for Trackme 1.0.8.
This is a source and synthetic-replay review, not outdoor accuracy certification.

## Reference implementations

The inspected revisions are pinned so that comparisons remain reproducible.
No implementation code was copied from these projects.

| Project | Recording policy inspected | Implication |
| --- | --- | --- |
| [OutRun](https://github.com/timfraedrich/OutRun/blob/2ffbffbf8b4140275ad8dcf0f6f1ebf1e8142ced/OutRunCore/Sources/OutRunCore/Recording/WorkoutRecorderState.swift) | Increasing timestamps; valid horizontal accuracy below a user setting; at least 0.5 s between recorded points; displacement above 5 m or an interval above 10 s. Adds native coordinate distance while recording. | No walking/running maximum-speed rejection in this acceptance path. Optional automatic pausing is a separate policy. |
| [OutRun preferences](https://github.com/timfraedrich/OutRun/blob/2ffbffbf8b4140275ad8dcf0f6f1ebf1e8142ced/OutRunCore/Sources/OutRunCore/UserPreferences/UserPreferences.swift) | Default accuracy limit 20 m; selectable values 10–50 m. | These are configurable product defaults, not an industry standard. |
| [OpenTracks recording](https://github.com/OpenTracksApp/OpenTracks/blob/3c23a9f5400c7b5b914a221469d76cc019a18296/src/main/java/de/dennisguse/opentracks/services/TrackRecordingManager.java) and [settings](https://github.com/OpenTracksApp/OpenTracks/blob/3c23a9f5400c7b5b914a221469d76cc019a18296/src/main/res/values/settings.xml) | Default 50 m accuracy gate, 10 m recording distance interval, automatic segment break beyond 200 m. Separate idle handling and optional sensor distance. | A 60 m displacement passes these default distance gates; copying them does not solve the reported jump. |
| [FitoTrack](https://codeberg.org/jannis/FitoTrack/src/commit/b60eb9d56ca5c4570130f1b86891659b4a75f504/app/src/main/java/de/tadris/fitness/recording/component/GpsSampleComponent.kt) | GPS samples are stored after a workout-specific minimum distance and minimum time interval. The GPS component requests updates every second and excludes cached locations older than 10 s. | Another sampling policy, not evidence for Trackme's 4.5 m/s walking cap. |

Apple defines [horizontal accuracy](https://developer.apple.com/documentation/corelocation/cllocation/horizontalaccuracy)
as a radius of uncertainty and [speed accuracy](https://developer.apple.com/documentation/corelocation/cllocation/speedaccuracy)
as uncertainty in the speed estimate. Neither establishes a walking speed cap,
a minimum walking speed, or a guaranteed error bound for rejecting outliers.
Instantaneous speed is also not an upper bound on travel over a preceding interval.

## Trackme 1.0.8 recording policy

- Request Core Location's best accuracy with the fitness activity type, no native
  distance filter, and automatic location pausing disabled. Background updates
  run only during active recording.
- Accept valid, chronological coordinates with reported horizontal accuracy
  within 50 m, including the first point after Resume or signal recovery.
- Record another point after at least 5 m of displacement from the last recorded
  point. Add the native horizontal distance between recorded coordinates.
- Do not gate distance on reported speed, inferred speed, or displacement relative
  to uncertainty radii. Slow walking and missing/uncertain speed follow the same
  spatial sampling rule as running.
- Keep the distance anchor separate from the latest usable measurement. Frequent
  stationary or slowly moving updates maintain signal continuity even when no
  new route point is needed.
- Clear the anchor at manual pauses and measurement gaps longer than 20 s. Do not
  add travel across these gaps. Resume excludes fixes measured before Resume.
  Delayed continuous batches remain connected using measurement timestamps.
- Save locally before HealthKit sync. HealthKit distance samples sum the same
  route legs per segment and do not span manual pauses.

This is a combination of source-backed policies, not a copy of another recorder:
50 m is OpenTracks' default recording accuracy and an OutRun option; 5 m is
OutRun's spatial sampling interval. Trackme does not adopt OutRun's time-triggered
recording or automatic pause policy. With manual pausing, there is no need to
add a new distance point just because time passed while stationary. Nor does it
add OpenTracks' 200 m segment-distance cutoff or sensor-distance integration.

The removed 0.35 m/s speed gate could reject slow walking indefinitely. The
removed uncertainty-radius fallback could discard short legs and turns even
with ongoing movement. The removed 4.5/12 m/s caps did not reliably distinguish
GPS errors from actual motion. Their superseded tests have been replaced with
slow-walking and speed-independent sampling regressions. The shared resume and
tracking accuracy gate is retained and covered by the recovery integration test.

## Numeric-policy provenance and limits

| Value | Rationale |
| --- | --- |
| 50 m recording accuracy | OpenTracks default; preserves recording availability in moderate reception. An accepted point can still be wrong. |
| 5 m spatial sampling | OutRun spatial interval; reduces dense small fluctuations without excluding slow motion. Short turns and an unsampled final tail can still undercount. |
| 25 m READY accuracy | Existing stricter start/status policy; does not prevent recovery while recording. Not an industry standard. |
| 20 s signal gap | Existing continuity policy; conservatively excludes unobserved travel. |
| 30 s READY lifetime, 5 s future tolerance/start-anchor age | Existing freshness policies, not distance calibration constants. |
| 20 m minimum saved workout | Existing product save rule, not a GPS accuracy threshold. |
| Elevation: 20 m accuracy, 3 m climb/reversal, 8 m or 4 m/s spike gate, five-point median | Independent existing elevation estimator, unchanged by this horizontal-distance review. These are heuristics, not standardized GPS constants. |

There is no claim of universal tracker thresholds or guaranteed GPS accuracy.
A plausible jump, including 60 m in 10 s with unavailable speed, may be recorded.
Stationary drift beyond the sampling interval may add distance. Coordinates and
reported uncertainty alone cannot reliably distinguish all such errors from real
travel. The simpler policy was selected with those limitations explicit rather
than adding another unvalidated outlier detector.

## Verification scope

Regression coverage includes slow walking with continuous fixes, missing and
uncertain speed, moderate-accuracy recovery, pauses, delayed background batches,
signal loss, duplicate timestamps, persistence, and HealthKit segment distances.
Simulator testing verifies lifecycle and saved-data consistency; it does not
reproduce real receiver noise or validate outdoor distance accuracy.

Outdoor evaluation should compare recorded distance against independently measured
routes, including slow walking, ordinary walking, running, repeated sharp turns,
stationary periods, obstructed reception, and pause/resume with a locked screen.
