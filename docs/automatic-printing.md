# Foreground auto-print

Auto-print starts off on a new installation. Legacy ASAP and scheduled preferences that were saved before activation existed are read as off. An explicit activation is retained across restarts.

Open Printer Settings for the selected location, save a printer, enable printing and select the order types to print. When requested, use **Activate auto-print for this account**. An activation is saved on this device for the account, location and order type.

- Paid and confirmed regular ASAP and catering orders are eligible on the next orders refresh. Catering prints once with its event time from `scheduledFor`, when provided.
- Paid and confirmed regular scheduled orders become eligible 30 minutes before `scheduledFor`. A late confirmation prints on the next refresh. Future scheduled orders already present at activation are included. Ticket times are in America/Los_Angeles.
- Preparing and Ready orders can recover while still eligible. Orders placed before activation that would print immediately are available for manual printing. Delivered and Cancelled orders are excluded from initial printing.
- Keep the app open in the foreground and signed in. The authenticated shell evaluates the existing order refresh every 15 seconds. A send already started may finish in the background.
- Use one auto-print device per location. Manual and automatic printing share a persistent initial job on that device. Pending jobs retain their original account, location and printer endpoint. Jobs created before account scoping require review because their account cannot be verified.
- Submitted indicates data was sent. Check the paper to verify physical output. Retry Failed before send manually with the original printer. Submitted, Confirmed and Unknown jobs are never retried automatically. After an uncertain send, check the paper before taking action.
- The client receives a bare orders list and detects HTTP 206. It has no verified pagination or total-count contract to detect a silent cap on HTTP 200. The foreground banner reports that discovery coverage cannot be verified. A production rollout requires a verified coverage contract or a paginated feed.
