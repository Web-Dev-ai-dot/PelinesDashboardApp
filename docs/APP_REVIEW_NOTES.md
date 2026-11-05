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

**How to sign in.** Use the demo administrator account below. This is the live
restaurant system, so please browse freely but avoid pausing online ordering,
changing store hours or cancelling orders.

- Email: `<demo-admin-email>`
- Password: `<demo-admin-password>`

**What you can try.** Sign in, choose the demo location on the home screen, and
open Today, Orders, Calendar and Menu. Orders can be
accepted and marked picked up or delivered from the order screens.

**Notes.**
- New-order alerts work while the app is open; the app does not use push
  notifications.
- Printing needs a network receipt printer, which a reviewer will not have. The
  Printer Settings screen can be left unconfigured.
- The privacy policy is at https://pelinesmexicanrestaurant.com/privacy and is
  linked from the sign-in screen and the Account screen.

## Before pasting this

1. The demo admin account exists on production (appreview@pelinesmexicanrestaurant.com).
   The password is kept outside this repository.
2. Test that exact login on the exact build you are submitting.
3. Enter the same privacy policy URL in the store listing form:
   `https://pelinesmexicanrestaurant.com/privacy`.
