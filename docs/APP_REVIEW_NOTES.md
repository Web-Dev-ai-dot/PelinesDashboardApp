# Pelines Admin: App Review Notes

Paste the text below into **App Store Connect → App Review Information → Notes**
and into **Play Console → App content → App access**. Fill in the two
`<...>` placeholders. Never commit real credentials to this repository.

## Notes for the reviewer

Pelines Admin is the staff app for Pelines Tequila & Mezcal (Troutdale and
Tualatin, Oregon). Restaurant managers use it to receive and manage customer
orders, edit the menu and set store hours.

**This app is for restaurant staff only.** There is no public sign-up because
staff accounts are created by the restaurant. For that reason the app has no
registration or account-deletion screen. Customers order through the separate
"Pelines" customer app and website, which do offer account deletion.

**How to sign in.** Use the demo administrator account below. It has full
administrator access but is limited to a demo/test location, so nothing you do
affects a real customer or a real order.

- Email: `<demo-admin-email>`
- Password: `<demo-admin-password>`

**What you can try.** Sign in, choose the demo location on the home screen, and
open Today, Orders, Calendar and Menu. Order status buttons (Accept, Ready,
Delivered) and menu edits work against the demo data only.

**Notes.**
- New-order alerts work while the app is open; the app does not use push
  notifications.
- Printing needs a network receipt printer, which a reviewer will not have. The
  Printer Settings screen can be left unconfigured.
- The privacy policy is at https://pelinesmexicanrestaurant.com/privacy and is
  linked from the sign-in screen and the Account screen.

## Before pasting this

1. Create a demo administrator account on the backend the submitted build points
   to, and a demo location it can use (so the reviewer cannot change a real
   store's hours or pause real online ordering).
2. Test that exact login on the exact build you are submitting.
3. Enter the same privacy policy URL in the store listing form:
   `https://pelinesmexicanrestaurant.com/privacy`.
