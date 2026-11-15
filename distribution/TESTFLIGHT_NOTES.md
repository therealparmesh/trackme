# TestFlight Notes

Please test the core walk and run flow:

## Workout Lifecycle

- Wait for READY, then start, pause, resume, and finish a workout.
- Walk outdoors with the screen locked for a minute or two. Unlock the phone,
  pause and walk briefly, then resume and keep walking. Finish and check that
  History includes the locked stretch and excludes the distance covered while paused.
- Review recent history and trends.

## GPS Accuracy and Recovery

- Before starting, confirm READY expires 30 seconds after the last accurate
  location was measured, including when a cached location arrives late.
- After finishing or discarding a workout, confirm READY still expires if no new
  location arrives.
- Before starting a workout, confirm a temporary location error disappears when
  an accurate fix restores READY.
- Leave an active workout stationary for several minutes, including with the
  screen locked, and note any distance added by GPS drift. Spatial sampling
  suppresses movements below 5 meters but does not guarantee zero drift.
- Walk slowly, including below 0.35 meters per second. Confirm distance continues
  accumulating as displacement reaches the 5-meter recording interval.
- Test standing still both at the start and during a workout, then begin
  walking. With continuous GPS updates, confirm route and distance tracking
  continue from the existing anchor. After a GPS gap, confirm recording resumes
  in a new segment without adding distance across the gap.
- If GPS briefly becomes weak, confirm accepted points continue the existing
  route without a discontinuity.
- If GPS is lost or interrupted, confirm recovery starts a new route segment
  without a distance jump.
- If GPS remains too inaccurate to record a route for more than 20 seconds,
  confirm recovery starts a new segment even if location updates kept arriving.

## Permission Changes and Restoration

- Pause a workout, turn off Location permission in Settings, and confirm Resume
  keeps it paused; restore permission and confirm Resume works.
- Turn off Precise Location and confirm the app points to Settings. Restore
  Precise Location and confirm the app can acquire a fix again.
- Reopen the app with an unfinished workout and Location permission off; confirm
  the workout is preserved and paused until permission is restored and Resume is
  tapped.

## Apple Health

- With auto-sync on, confirm the walk appears in Apple Health after it saves in
  History. Compare workout distance and check the route in Fitness.
- Delete a synced workout from its detail screen and confirm its Apple Health
  workout, distance, and route are removed.

Please include the iPhone model, iOS version, and any context that helps explain
the issue.
