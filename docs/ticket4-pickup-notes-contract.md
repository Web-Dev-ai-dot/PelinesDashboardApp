# Ticket 4.1 / 4.2 — Pickup notes contract

Verified 2026-10-02 without creating or mutating orders.

## Evidence

- Existing staging order TRO-2610-0008 displays the exact customer note
  `Included items (forks, napkins, etc.): yes` in the authenticated web admin.
- Public checkout bundle inspected:
  https://pelines-staging.vercel.app/_next/static/chunks/1208f4a81632b71c.js?dpl=dpl_6bqsJu7aRPKmkPMGPN8gPHYmoMD1
- Its submit handler constructs `notes` as follows (variable names expanded):

```js
[
  isCatering ? '' : `Included items (forks, napkins, etc.): ${includeUtensils ? 'yes' : 'no'}`,
  customerNote.trim(),
].filter(Boolean).join('\n') || undefined
```

`isCatering` is `orderType === 'catering'`. The result is sent in the
`POST /orders` body as `notes`. Item notes are sent separately in `items[].notes`.
Catering sends `eventDetails.eventName`, not utensils or pickup instructions.
The generated utensils prefix applies to Regular checkout, including delivery.
The checkbox is bound to boolean form state (`checked: z`,
`onChange: e => A(e.target.checked)` in the deployed bundle). That same `z`
selects `yes`/`no` in the serializer above. Backend `CreateOrderDto.notes`
accepts the text; `OrdersService.create` writes `notes: dto.notes`; admin GET
returns the persisted scalar, and web `mapApiOrder` maps `notes: o.notes`.
There is no dedicated persisted `includeUtensils` field in this contract.

Backend staging `46c56494c301d43ad887c9fe2442f28542747cac` accepts a free-text
`notes` string (500 characters) and persists it unchanged. Flutter reads that
field as `OrderDetail.notes`. This is a checkout text convention, not a typed
backend utensils field. No authenticated raw JSON export was obtained; live
evidence is the admin rendering, corroborated by its notes adapter and the
checkout producer code.

## Detail presentation

Only Regular (`online`), Pickup, `source == 'web'` orders are split. Only an
exact first line ending in lowercase `yes` or `no` is recognized. The first
newline and generated line are removed from the displayed Customer Notes;
all remaining characters are preserved, even repeated or contradictory text.
The original model/repository value and printing input are unchanged.
Unknown source/format, other order types and Delivery retain the full note.
Missing data does not imply No. Item notes and arbitrary JSON keys are not parsed.
Ticket 4.2 keeps Customer Notes as an independent card with a discreet empty
state when no customer text remains, whether or not utensils were provided.
Utensils has the same circular-icon/label/value layout as the other pickup rows.

## Pickup Instructions

The checkout's Pickup Instructions is static arrival guidance, composed using
the current location name. It is not sent in the create-order payload. The web
admin similarly renders fallback guidance. No per-order instructions contract
was found. Ticket 4.2 explicitly authorizes mirroring the customer formatter:

`Arrive at {location} at your pickup time, head to the front counter, and let the team know you are picking up an online order.`

`pickup_instructions.dart` formats this guidance using the real location name
and localizes the surrounding text for EN/ES. Missing/blank names fall back to
`Pelines` (checkout uses `location?.name ?? 'Pelines'`). No location-specific
address or instructions are hardcoded. The result is shown only for Pickup,
in a quoted, italic callout, separate from customer/item/staff notes. It is
generated guidance, not stored per-order data. A future canonical backend
instruction field would require replacing this formatter's source.

## Existing risk outside this ticket

The prior audit found potential exposure of `internalNotes` through
`GET /orders/mine`. Ticket 4/4.1 do not modify that backend behavior.
