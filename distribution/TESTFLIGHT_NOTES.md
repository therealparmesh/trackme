# TestFlight Notes

Please test the core walk and run flow:

- Wait for READY, then start, pause, resume, and finish a workout
- Before starting, confirm READY expires 30 seconds after the last accurate location was measured, including when a cached location arrives late
- After finishing or discarding a workout, confirm READY still expires if no new location arrives
- Pause a workout, turn off Location permission in Settings, and confirm Resume keeps it paused; restore permission and confirm Resume works
- Reopen the app with an unfinished workout and Location permission off; confirm the workout is preserved and paused until permission is restored and Resume is tapped
- Before starting a workout, confirm a temporary location error disappears when an accurate fix restores READY
- Allow Motion & Fitness access when prompted after starting a workout
- Leave an active workout stationary for several minutes, including with the screen locked, and confirm distance does not increase while elapsed time continues
- Start a workout while stationary, then begin walking and confirm route and distance tracking resume from the starting location
- After standing still during a workout, begin walking and confirm there is no immediate signal-loss warning or discarded starting segment
- Check the live map and saved workout summary
- Review recent history and trends
- Confirm Apple Health sync adds completed workouts when permission is granted
- Delete a synced workout from its detail screen and confirm its Apple Health workout, distance, and route are removed
- If GPS briefly becomes weak, confirm accepted points continue the existing route without a discontinuity
- If GPS is lost or interrupted, confirm recovery starts a new route segment without a distance jump
- If GPS remains too inaccurate to record a route for more than 20 seconds, confirm recovery starts a new segment even if location updates kept arriving

Please include the iPhone model, iOS version, and any context that helps explain the issue.
