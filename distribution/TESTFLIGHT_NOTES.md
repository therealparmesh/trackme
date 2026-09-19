# TestFlight Notes

Please test the core walk and run flow:

## Workout Lifecycle

- Wait for READY, then start, pause, resume, and finish a workout.
- Allow Motion & Fitness access when prompted after starting a workout.
- Check the live map and saved workout summary.
- Review recent history and trends.

## GPS Accuracy and Recovery

- Before starting, confirm READY expires 30 seconds after the last accurate
  location was measured, including when a cached location arrives late.
- Leave an active workout stationary for several minutes, including with the
  screen locked, and confirm distance does not increase while elapsed time
  continues.
- Test standing still both at the start and during a workout, then begin
  walking. Confirm route and distance tracking continue from the existing anchor
  without an immediate signal-loss warning.
- If GPS briefly becomes weak, confirm accepted points continue the existing
  route without a discontinuity.
- If GPS is lost or interrupted, confirm recovery starts a new route segment
  without a distance jump.
- If GPS remains too inaccurate to record a route for more than 20 seconds,
  confirm recovery starts a new segment even if location updates kept arriving.

## Apple Health

- Confirm Apple Health sync adds completed workouts when permission is granted.
- Delete a synced workout from its detail screen and confirm its Apple Health
  workout, distance, and route are removed.

Please include the iPhone model, iOS version, and any context that helps explain
the issue.
