# trackme App Review Notes

trackme records outdoor walks and runs using Core Location. No account or login
is required.

## Review Steps

1. Launch the app. Apple Health and Location access are requested on startup.
2. On Track, choose Walk or Run.
3. If prompted, allow Location access with Precise Location enabled.
4. Wait for the status to show READY, then tap Start.
5. Move with the device to record route and distance data.
6. To check background recording, lock the screen while walking. Unlock it,
   pause, then resume the workout.
7. Tap Finish. The workout saves on the device and the app opens History.
8. Open the workout to view its route and summary. The top-right menu can delete
   it.

## HealthKit

With permission and auto-sync enabled, trackme adds completed workouts, distance,
and routes to Apple Health after saving the workout on the device. trackme
queries the HealthKit records it created when deleting a synced workout. It does
not request read access to the user's broader Health data or use Health data for
advertising or data mining.

## Background Location

Background location updates are enabled only while a workout is actively
recording. Pausing or finishing stops background recording. The location
indicator is shown while background tracking is active. The Track screen looks
for a fresh GPS fix after finishing so the next workout can start.

## Location Accuracy

The Start button is disabled until a recent, accurate location fix is available.
Before a workout starts, READY expires 30 seconds after that fix was measured,
including when a cached fix arrives late. During a workout, trackme uses Core
Location with the fitness activity type, continuous background updates, and
automatic location pausing disabled. Location timestamps, horizontal accuracy,
speed, and displacement filter stale fixes and small GPS drift. Each route
segment begins from an accurate location anchor. Pauses and gaps of more than
20 seconds between usable GPS measurements start new route segments so missing
stretches do not inflate distance. Delayed batches of continuous GPS
measurements remain connected.

## Payments

trackme has no purchases, subscriptions, paywall, or account system.
