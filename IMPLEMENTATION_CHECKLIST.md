# Authenticated workspace implementation checklist

- [x] Camera QR scanning selects an open event and calls the administrator-only `admin_check_in` RPC.
- [x] Explicit camera start, rear-camera preference, pause/resume/stop, duplicate-safe check-in, manual token fallback, and lifecycle cleanup.
- [x] One runtime-generated Teacher Workspace navigation shell across every administrator route.
- [x] Points page member selector uses `admin_member_directory`; awards use the bank-backed administrator RPC.
- [x] Event detail bulk awards checked-in attendees with `admin_award_event_points` and idempotent source keys.
- [x] Compact inline “Publish now” and other checkbox labels.
- [x] Recognition moderation uses Respond plus Public/Private choices.
- [x] Separate administrator Request Feedback workflow and member response workflow.
- [x] Compact recognition, feedback, and notification previews.
- [x] Member notifications for attendance, points, badges, recognition reviews, and feedback requests; administrator notification/feedback queues.
- [x] Role-aware tours target real controls and provide Back, Next, Skip, Finish, and replay.
- [x] Persistent Spanish localization covers shared authenticated navigation, workflows, buttons, forms, status messages, and generated dialogs.
- [x] Responsive navigation, forms, tables, scanner, dialogs, cards, and touch targets across authenticated routes.

Camera behavior must still be verified on physical iOS and Android hardware because automated tests cannot grant a real mobile camera stream.
